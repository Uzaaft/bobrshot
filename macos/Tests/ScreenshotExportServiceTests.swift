import Foundation
import XCTest

final class ScreenshotExportServiceTests: XCTestCase {
    private static let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    func testExportsOptimizedPNGWithSanitizedName() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        let service = ScreenshotExportService(
            clock: { Date(timeIntervalSince1970: 0) },
            makeIdentifier: { identifier }
        )

        let result = try await service.export(
            ScreenshotExportRequest(
                data: Self.png,
                directory: directory,
                filenamePrefix: "Bobrshot/Unsafe",
                optimize: true
            )
        )

        XCTAssertEqual(result.format, .png)
        XCTAssertEqual(
            result.url.lastPathComponent, "Bobrshot-Unsafe 1970-01-01 at 00.00.00 00112233.png")
        XCTAssertEqual(try Data(contentsOf: result.url).count, result.byteCount)
        XCTAssertGreaterThanOrEqual(result.bytesRemoved, 0)
        XCTAssertNil(result.securityScopedBookmark)
    }

    func testNeverOverwritesAnExistingExport() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        let service = ScreenshotExportService(
            clock: { Date(timeIntervalSince1970: 0) },
            makeIdentifier: { identifier }
        )
        let request = ScreenshotExportRequest(data: Self.png, directory: directory)
        let first = try await service.export(request)

        do {
            _ = try await service.export(request)
            XCTFail("A colliding export unexpectedly replaced the original")
        } catch ScreenshotExportError.exhaustedFilenameAttempts {
            XCTAssertEqual(try Data(contentsOf: first.url), Self.png)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsUnsupportedImageBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ScreenshotExportService()

        do {
            _ = try await service.export(
                ScreenshotExportRequest(data: Data([0, 1, 2]), directory: directory)
            )
            XCTFail("Unsupported bytes were exported")
        } catch ScreenshotExportError.unsupportedImageFormat {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bobrshot-export-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
