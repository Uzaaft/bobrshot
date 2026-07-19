import Foundation
import XCTest

final class RecordingDestinationAllocatorTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 0)
    private let fixedIdentifier = UUID(uuidString: "12345678-1234-5678-9ABC-DEF012345678")!

    func testAllocatesSanitizedMovieNameAndCreatesDirectory() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let directory = parent.appendingPathComponent("Recordings")
        defer { try? FileManager.default.removeItem(at: parent) }
        let allocator = makeAllocator()

        let reservation = try allocator.allocate(
            in: directory,
            filenamePrefix: "  Demo/Clip:\n  "
        )
        defer { allocator.release(reservation) }

        XCTAssertEqual(
            reservation.destinationURL.lastPathComponent,
            "Demo-Clip-- 1970-01-01 at 00.00.00 12345678-1234-5678-9abc-def012345678.mov"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.destinationURL.path))
    }

    func testConcurrentAllocationWithSameIdentifierIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let allocator = makeAllocator(maximumAttempts: 1)
        let first = try allocator.allocate(in: directory)
        defer { allocator.release(first) }

        XCTAssertThrowsError(try allocator.allocate(in: directory)) { error in
            XCTAssertEqual(
                error as? RecordingDestinationError,
                .exhaustedFilenameAttempts
            )
        }
    }

    func testExistingMovieIsNeverSelected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let allocator = makeAllocator(maximumAttempts: 1)
        let first = try allocator.allocate(in: directory)
        allocator.release(first)
        try Data("existing".utf8).write(to: first.destinationURL)

        XCTAssertThrowsError(try allocator.allocate(in: directory)) { error in
            XCTAssertEqual(
                error as? RecordingDestinationError,
                .exhaustedFilenameAttempts
            )
        }
        XCTAssertEqual(try Data(contentsOf: first.destinationURL), Data("existing".utf8))
    }

    func testRejectsNonFileDirectoryAndFileAtDirectoryPath() throws {
        let allocator = makeAllocator()
        XCTAssertThrowsError(try allocator.allocate(in: URL(string: "https://example.com")!)) {
            error in
            XCTAssertEqual(error as? RecordingDestinationError, .directoryMustBeFileURL)
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data().write(to: fileURL)
        XCTAssertThrowsError(try allocator.allocate(in: fileURL)) { error in
            guard case .cannotCreateDirectory(let url, _) = error as? RecordingDestinationError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, fileURL)
        }
    }

    private func makeAllocator(maximumAttempts: Int = 32) -> RecordingDestinationAllocator {
        let date = fixedDate
        let identifier = fixedIdentifier
        return RecordingDestinationAllocator(
            clock: { date },
            makeIdentifier: { identifier },
            maximumAttempts: maximumAttempts
        )
    }
}
