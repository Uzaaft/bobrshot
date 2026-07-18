import Foundation
import XCTest

final class NativeImageProbeTests: XCTestCase {
    func testInspectsPNGDimensionsAndFrameCount() throws {
        guard
            let data = Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        else {
            XCTFail("PNG fixture is invalid")
            return
        }

        let descriptor = try NativeImageProbe.inspect(data)

        XCTAssertEqual(descriptor.format, .png)
        XCTAssertEqual(descriptor.widthPixels, 1)
        XCTAssertEqual(descriptor.heightPixels, 1)
        XCTAssertEqual(descriptor.frameCount, 1)
    }

    func testRejectsUnsupportedData() {
        do {
            _ = try NativeImageProbe.inspect(Data([0x00, 0x01]))
            XCTFail("Unsupported data was accepted")
        } catch NativeImageProbeError.unsupportedFormat {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsTruncatedRecognizedData() {
        let truncatedPNG = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

        do {
            _ = try NativeImageProbe.inspect(truncatedPNG)
            XCTFail("Truncated PNG was accepted")
        } catch NativeImageProbeError.invalidContainer {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
