import Foundation

enum CaptureArtifactKind: Codable, Equatable, Hashable, Sendable {
    case screenshot(ScreenshotFileFormat)
    case screenRecording(RecordingVideoCodec)
}

struct CaptureHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let fileURL: URL
    let kind: CaptureArtifactKind
    let byteCount: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
    /// Present for files exported outside the app container. Plain URLs alone do not preserve
    /// sandbox access across launches.
    let securityScopedBookmark: Data?

    var format: ScreenshotFileFormat? {
        guard case let .screenshot(format) = kind else { return nil }
        return format
    }

    init(
        id: UUID = UUID(),
        createdAt: Date,
        fileURL: URL,
        kind: CaptureArtifactKind,
        byteCount: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        securityScopedBookmark: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.kind = kind
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.securityScopedBookmark = securityScopedBookmark
    }

    init(
        id: UUID = UUID(),
        createdAt: Date,
        fileURL: URL,
        format: ScreenshotFileFormat,
        byteCount: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        securityScopedBookmark: Data? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            fileURL: fileURL,
            kind: .screenshot(format),
            byteCount: byteCount,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            securityScopedBookmark: securityScopedBookmark
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case fileURL
        case kind
        case format
        case byteCount
        case pixelWidth
        case pixelHeight
        case securityScopedBookmark
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        if let decodedKind = try container.decodeIfPresent(CaptureArtifactKind.self, forKey: .kind)
        {
            kind = decodedKind
        } else {
            kind = .screenshot(try container.decode(ScreenshotFileFormat.self, forKey: .format))
        }
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        securityScopedBookmark = try container.decodeIfPresent(
            Data.self, forKey: .securityScopedBookmark)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(kind, forKey: .kind)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encodeIfPresent(pixelWidth, forKey: .pixelWidth)
        try container.encodeIfPresent(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(securityScopedBookmark, forKey: .securityScopedBookmark)
    }
}

enum CaptureHistoryError: Error, Equatable, LocalizedError {
    case invalidLimit
    case corruptStore(String)
    case persistenceFailed(String)
    case securityScopedBookmarkFailed(String)
    case invalidFileSize(Int64)

    var errorDescription: String? {
        switch self {
        case .invalidLimit:
            "Capture history must retain at least one item."
        case let .corruptStore(message):
            "Capture history could not be decoded: \(message)"
        case let .persistenceFailed(message):
            "Capture history could not be saved: \(message)"
        case let .securityScopedBookmarkFailed(message):
            "A capture file bookmark could not be resolved: \(message)"
        case let .invalidFileSize(size):
            "The capture file size \(size) cannot be represented in history."
        }
    }
}

actor CaptureHistoryStore {
    typealias Clock = @Sendable () -> Date

    private struct Archive: Codable {
        let version: Int
        var entries: [CaptureHistoryEntry]
    }

    private static let archiveVersion = 2

    private let archiveURL: URL
    private let maximumEntryCount: Int
    private let fileManager: FileManager
    private let clock: Clock
    private var cachedEntries: [CaptureHistoryEntry]?

    init(
        directory: URL,
        maximumEntryCount: Int = 100,
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() }
    ) throws {
        guard maximumEntryCount > 0 else { throw CaptureHistoryError.invalidLimit }
        self.archiveURL = directory.appendingPathComponent("capture-history.json")
        self.maximumEntryCount = maximumEntryCount
        self.fileManager = fileManager
        self.clock = clock
    }

    func entries() throws -> [CaptureHistoryEntry] {
        try loadIfNeeded()
    }

    func data(for entry: CaptureHistoryEntry) throws -> Data {
        try withFileAccess(for: entry) { url in
            try Data(contentsOf: url)
        }
    }

    @discardableResult
    func add(
        _ export: ExportedScreenshot,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) throws -> CaptureHistoryEntry {
        var current = try loadIfNeeded()
        let entry = CaptureHistoryEntry(
            createdAt: clock(),
            fileURL: export.url,
            kind: .screenshot(export.format),
            byteCount: export.byteCount,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            securityScopedBookmark: export.securityScopedBookmark
        )
        current.removeAll { $0.id == entry.id }
        current.append(entry)
        current.sort(by: Self.newestFirst)
        if current.count > maximumEntryCount {
            current.removeLast(current.count - maximumEntryCount)
        }
        try persist(current)
        return entry
    }

    @discardableResult
    func add(
        _ recording: ScreenRecordingResult,
        codec: RecordingVideoCodec
    ) throws -> CaptureHistoryEntry {
        guard let byteCount = Int(exactly: recording.fileSize), byteCount >= 0 else {
            throw CaptureHistoryError.invalidFileSize(recording.fileSize)
        }
        var current = try loadIfNeeded()
        let entry = CaptureHistoryEntry(
            createdAt: clock(),
            fileURL: recording.url,
            kind: .screenRecording(codec),
            byteCount: byteCount
        )
        current.append(entry)
        current.sort(by: Self.newestFirst)
        if current.count > maximumEntryCount {
            current.removeLast(current.count - maximumEntryCount)
        }
        try persist(current)
        return entry
    }

    /// Removes metadata and optionally the exported file. File deletion resolves and balances a
    /// persisted security-scoped bookmark when one is present.
    @discardableResult
    func remove(id: UUID, deleteFile: Bool = false) throws -> CaptureHistoryEntry? {
        var current = try loadIfNeeded()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = current.remove(at: index)
        if deleteFile {
            try withFileAccess(for: removed) { url in
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        }
        try persist(current)
        return removed
    }

    /// Applies a smaller retention limit immediately. The configured maximum still applies to
    /// future additions. Setting `deleteFiles` is intentionally opt-in.
    @discardableResult
    func prune(keepingNewest count: Int, deleteFiles: Bool = false) throws -> [CaptureHistoryEntry]
    {
        guard count >= 0 else { throw CaptureHistoryError.invalidLimit }
        var current = try loadIfNeeded()
        guard current.count > count else { return [] }
        let removed = Array(current.dropFirst(count))
        if deleteFiles {
            for entry in removed {
                try withFileAccess(for: entry) { url in
                    if fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                }
            }
        }
        current.removeLast(current.count - count)
        try persist(current)
        return removed
    }

    /// Removes records whose files no longer exist. Security-scoped bookmarks are resolved before
    /// checking because a persisted plain URL may not be accessible in the app sandbox.
    @discardableResult
    func pruneMissingFiles() throws -> [CaptureHistoryEntry] {
        var current = try loadIfNeeded()
        var removed: [CaptureHistoryEntry] = []
        for entry in current where try !fileExists(for: entry) {
            removed.append(entry)
        }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        current.removeAll { removedIDs.contains($0.id) }
        try persist(current)
        return removed
    }

    @discardableResult
    func removeAll(deleteFiles: Bool = false) throws -> [CaptureHistoryEntry] {
        let current = try loadIfNeeded()
        if deleteFiles {
            for entry in current {
                try withFileAccess(for: entry) { url in
                    if fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                }
            }
        }
        try persist([])
        return current
    }

    private func loadIfNeeded() throws -> [CaptureHistoryEntry] {
        if let cachedEntries { return cachedEntries }
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            cachedEntries = []
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(
                Archive.self,
                from: Data(contentsOf: archiveURL)
            )
            guard (1...Self.archiveVersion).contains(archive.version) else {
                throw CaptureHistoryError.corruptStore(
                    "Unsupported archive version \(archive.version).")
            }
            let bounded = Array(
                archive.entries.sorted(by: Self.newestFirst).prefix(maximumEntryCount))
            cachedEntries = bounded
            if bounded.count != archive.entries.count || archive.version != Self.archiveVersion {
                try persist(bounded)
            }
            return bounded
        } catch let error as CaptureHistoryError {
            throw error
        } catch {
            throw CaptureHistoryError.corruptStore(error.localizedDescription)
        }
    }

    private func persist(_ entries: [CaptureHistoryEntry]) throws {
        do {
            try fileManager.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                Archive(version: Self.archiveVersion, entries: entries)
            )
            try data.write(to: archiveURL, options: .atomic)
            cachedEntries = entries
        } catch {
            throw CaptureHistoryError.persistenceFailed(error.localizedDescription)
        }
    }

    private func fileExists(for entry: CaptureHistoryEntry) throws -> Bool {
        try withFileAccess(for: entry) { url in
            fileManager.fileExists(atPath: url.path)
        }
    }

    private func withFileAccess<T>(
        for entry: CaptureHistoryEntry,
        operation: (URL) throws -> T
    ) throws -> T {
        guard let bookmark = entry.securityScopedBookmark else {
            return try operation(entry.fileURL)
        }
        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw CaptureHistoryError.securityScopedBookmarkFailed(
                    "Access to \(resolvedURL.path) was denied."
                )
            }
            defer { resolvedURL.stopAccessingSecurityScopedResource() }
            return try operation(resolvedURL)
        } catch let error as CaptureHistoryError {
            throw error
        } catch {
            throw CaptureHistoryError.securityScopedBookmarkFailed(error.localizedDescription)
        }
    }

    private static func newestFirst(_ lhs: CaptureHistoryEntry, _ rhs: CaptureHistoryEntry) -> Bool
    {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
