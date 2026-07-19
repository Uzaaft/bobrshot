import Foundation
import XCTest

final class CaptureHistoryStoreTests: XCTestCase {
    func testPersistsAndReloadsBoundedHistory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureHistoryStore(
            directory: directory,
            maximumEntryCount: 2,
            clock: { Date(timeIntervalSince1970: 1_234) }
        )

        for index in 0..<3 {
            _ = try await store.add(export(at: directory, name: "capture-\(index).png"))
        }
        let retained = try await store.entries()
        XCTAssertEqual(retained.count, 2)

        let reloaded = try CaptureHistoryStore(directory: directory, maximumEntryCount: 2)
        let persisted = try await reloaded.entries()
        XCTAssertEqual(persisted, retained)
        XCTAssertEqual(persisted.first?.createdAt, Date(timeIntervalSince1970: 1_234))
    }

    func testPrunesMissingFilesAndCanDeleteRetainedFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureHistoryStore(directory: directory)
        let present = export(at: directory, name: "present.png")
        let missing = export(at: directory, name: "missing.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1]).write(to: present.url)
        let presentEntry = try await store.add(present)
        let missingEntry = try await store.add(missing)

        let pruned = try await store.pruneMissingFiles()
        XCTAssertEqual(pruned.map(\.id), [missingEntry.id])
        let retained = try await store.entries()
        XCTAssertEqual(retained.map(\.id), [presentEntry.id])

        _ = try await store.remove(id: presentEntry.id, deleteFile: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: present.url.path))
        let emptied = try await store.entries()
        XCTAssertTrue(emptied.isEmpty)
    }

    func testRejectsInvalidRetentionLimit() {
        XCTAssertThrowsError(
            try CaptureHistoryStore(directory: temporaryDirectory(), maximumEntryCount: 0)
        ) {
            error in
            XCTAssertEqual(error as? CaptureHistoryError, .invalidLimit)
        }
    }

    private func export(at directory: URL, name: String) -> ExportedScreenshot {
        ExportedScreenshot(
            url: directory.appendingPathComponent(name),
            format: .png,
            byteCount: 1,
            bytesRemoved: 0,
            securityScopedBookmark: nil
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bobrshot-history-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
