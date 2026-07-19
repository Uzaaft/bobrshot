import Foundation

enum ScreenshotFileFormat: String, Codable, CaseIterable, Sendable {
    case png
    case jpeg
    case gif
    case webP
    case tiff
    case heic
    case heif

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .webP: "webp"
        case .tiff: "tiff"
        case .heic: "heic"
        case .heif: "heif"
        }
    }

    fileprivate init(_ format: CoreImageFormat) {
        switch format {
        case .png: self = .png
        case .jpeg: self = .jpeg
        case .gif: self = .gif
        case .webP: self = .webP
        case .tiff: self = .tiff
        case .heic: self = .heic
        case .heif: self = .heif
        }
    }
}

/// Describes who owns access to an export directory.
///
/// Use `securityScoped` only for a URL selected outside the app container. The exporter balances
/// `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()` and stores
/// a bookmark in the result so a history entry can resolve the file in a future process.
enum ExportDirectoryAccess: Sendable {
    case appOwned
    case securityScoped
}

struct ScreenshotExportRequest: Sendable {
    let data: Data
    let directory: URL
    var filenamePrefix: String = "Bobrshot"
    var optimize: Bool = true
    var directoryAccess: ExportDirectoryAccess = .appOwned
}

struct ExportedScreenshot: Equatable, Sendable {
    let url: URL
    let format: ScreenshotFileFormat
    let byteCount: Int
    let bytesRemoved: Int
    let securityScopedBookmark: Data?
}

enum ScreenshotExportError: Error, Equatable, LocalizedError {
    case unsupportedImageFormat
    case securityScopedAccessDenied(URL)
    case cannotCreateDirectory(URL, String)
    case cannotWriteFile(String)
    case exhaustedFilenameAttempts

    var errorDescription: String? {
        switch self {
        case .unsupportedImageFormat:
            "The screenshot data is not in a supported image format."
        case let .securityScopedAccessDenied(url):
            "Access to the selected export directory was denied: \(url.path)"
        case let .cannotCreateDirectory(url, message):
            "The export directory could not be created at \(url.path): \(message)"
        case let .cannotWriteFile(message):
            "The screenshot could not be written: \(message)"
        case .exhaustedFilenameAttempts:
            "A unique screenshot filename could not be allocated."
        }
    }
}

actor ScreenshotExportService {
    typealias Clock = @Sendable () -> Date
    typealias Identifier = @Sendable () -> UUID

    private let fileManager: FileManager
    private let clock: Clock
    private let makeIdentifier: Identifier

    init(
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() },
        makeIdentifier: @escaping Identifier = { UUID() }
    ) {
        self.fileManager = fileManager
        self.clock = clock
        self.makeIdentifier = makeIdentifier
    }

    func export(_ request: ScreenshotExportRequest) throws -> ExportedScreenshot {
        try withDirectoryAccess(request.directory, access: request.directoryAccess) {
            try createDirectoryIfNeeded(request.directory)

            guard let detectedFormat = BobrshotCore.detectImageFormat(request.data) else {
                throw ScreenshotExportError.unsupportedImageFormat
            }

            let originalByteCount = request.data.count
            let output: Data
            let format: ScreenshotFileFormat
            if request.optimize {
                let result = try BobrshotCore.optimizeImage(request.data)
                output = result.data
                format = ScreenshotFileFormat(result.format)
            } else {
                output = request.data
                format = ScreenshotFileFormat(detectedFormat)
            }

            let prefix = Self.sanitizedPrefix(request.filenamePrefix)
            let timestamp = Self.filenameTimestamp(clock())
            let exportedURL = try writeWithoutCollision(
                output,
                directory: request.directory,
                stem: "\(prefix) \(timestamp)",
                extension: format.fileExtension
            )
            let bookmark = try makeBookmarkIfNeeded(
                for: exportedURL,
                access: request.directoryAccess
            )
            return ExportedScreenshot(
                url: exportedURL,
                format: format,
                byteCount: output.count,
                bytesRemoved: originalByteCount - output.count,
                securityScopedBookmark: bookmark
            )
        }
    }

    private func createDirectoryIfNeeded(_ directory: URL) throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ScreenshotExportError.cannotCreateDirectory(
                directory,
                error.localizedDescription
            )
        }
    }

    private func writeWithoutCollision(
        _ data: Data,
        directory: URL,
        stem: String,
        extension fileExtension: String
    ) throws -> URL {
        // A completed same-volume temporary file is hard-linked into place. `link(2)` is atomic and
        // refuses to replace an existing destination, unlike Foundation's atomic Data write (which
        // cannot be combined with `.withoutOverwriting`).
        for _ in 0..<32 {
            let suffix = makeIdentifier().uuidString.prefix(8).lowercased()
            let url =
                directory
                .appendingPathComponent("\(stem) \(suffix)")
                .appendingPathExtension(fileExtension)
            let temporaryURL = directory.appendingPathComponent(
                ".bobrshot-export-\(UUID().uuidString).tmp"
            )
            do {
                try data.write(to: temporaryURL, options: .withoutOverwriting)
                defer { try? fileManager.removeItem(at: temporaryURL) }
                try fileManager.linkItem(at: temporaryURL, to: url)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                throw ScreenshotExportError.cannotWriteFile(error.localizedDescription)
            }
        }
        throw ScreenshotExportError.exhaustedFilenameAttempts
    }

    private func withDirectoryAccess<T>(
        _ directory: URL,
        access: ExportDirectoryAccess,
        operation: () throws -> T
    ) throws -> T {
        guard case .securityScoped = access else {
            return try operation()
        }
        guard directory.startAccessingSecurityScopedResource() else {
            throw ScreenshotExportError.securityScopedAccessDenied(directory)
        }
        defer { directory.stopAccessingSecurityScopedResource() }
        return try operation()
    }

    private func makeBookmarkIfNeeded(
        for url: URL,
        access: ExportDirectoryAccess
    ) throws -> Data? {
        guard case .securityScoped = access else { return nil }
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw ScreenshotExportError.cannotWriteFile(
                "The file was written, but its security-scoped bookmark could not be saved: "
                    + error.localizedDescription
            )
        }
    }

    private static func sanitizedPrefix(_ prefix: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:").union(.newlines).union(.controlCharacters)
        let sanitized = prefix.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Bobrshot" : String(sanitized.prefix(80))
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        guard let utc = TimeZone(secondsFromGMT: 0) else { return "unknown-date" }
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: utc,
            from: date
        )
        return String(
            format: "%04d-%02d-%02d at %02d.%02d.%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
