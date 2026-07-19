import XCTest

final class RecordingConfigurationPlannerTests: XCTestCase {
    private let catalog = CaptureCatalog(
        displays: [
            CaptureDisplay(
                id: 11,
                name: "Display 1",
                frame: CaptureRect(x: 0, y: 0, width: 1_001, height: 801),
                pixelWidth: 2_002,
                pixelHeight: 1_602
            )
        ],
        windows: []
    )

    func testBuildsEncoderSafePlan() throws {
        let plan = try RecordingConfigurationPlanner.plan(
            target: .display(DisplayCaptureTarget(displayID: 11)),
            catalog: catalog,
            options: ScreenRecordingOptions(codec: .hevc, framesPerSecond: 30)
        )

        XCTAssertEqual(plan.width, 2_002)
        XCTAssertEqual(plan.height, 1_602)
        XCTAssertEqual(plan.framesPerSecond, 30)
        XCTAssertGreaterThanOrEqual(plan.videoBitRate, 2_000_000)
    }

    func testRoundsOddRegionDimensionsDownForVideoEncoder() throws {
        let plan = try RecordingConfigurationPlanner.plan(
            target: .region(
                RegionCaptureTarget(
                    displayID: 11,
                    rect: CaptureRect(x: 0, y: 0, width: 100.5, height: 80.5)
                )
            ),
            catalog: catalog,
            options: ScreenRecordingOptions(framesPerSecond: 60)
        )

        XCTAssertEqual(plan.width % 2, 0)
        XCTAssertEqual(plan.height % 2, 0)
        XCTAssertEqual(plan.width, 200)
        XCTAssertEqual(plan.height, 160)
    }

    func testRejectsInvalidFrameRateAndBitRate() {
        XCTAssertThrowsError(
            try RecordingConfigurationPlanner.plan(
                target: .display(DisplayCaptureTarget(displayID: 11)),
                catalog: catalog,
                options: ScreenRecordingOptions(framesPerSecond: 0)
            )
        ) { error in
            XCTAssertEqual(error as? ScreenRecordingError, .invalidFrameRate(0))
        }

        XCTAssertThrowsError(
            try RecordingConfigurationPlanner.plan(
                target: .display(DisplayCaptureTarget(displayID: 11)),
                catalog: catalog,
                options: ScreenRecordingOptions(videoBitRate: -1)
            )
        ) { error in
            XCTAssertEqual(error as? ScreenRecordingError, .invalidVideoBitRate(-1))
        }
    }
}
