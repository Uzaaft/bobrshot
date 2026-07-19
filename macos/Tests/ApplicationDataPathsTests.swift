import Foundation
import XCTest

final class ApplicationDataPathsTests: XCTestCase {
    func testBuildsStableAppOwnedLayout() {
        let support = URL(fileURLWithPath: "/tmp/fixture-support", isDirectory: true)
        let paths = ApplicationDataPaths(applicationSupportDirectory: support)

        XCTAssertEqual(paths.root.path, "/tmp/fixture-support/Bobrshot")
        XCTAssertEqual(paths.screenshots.path, "/tmp/fixture-support/Bobrshot/Screenshots")
        XCTAssertEqual(paths.recordings.path, "/tmp/fixture-support/Bobrshot/Recordings")
        XCTAssertEqual(paths.state.path, "/tmp/fixture-support/Bobrshot/State")
    }

    func testPrepareCreatesEveryDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("bobrshot-path-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: base)

        try paths.prepare()

        for directory in [paths.root, paths.screenshots, paths.recordings, paths.state] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
    }
}
