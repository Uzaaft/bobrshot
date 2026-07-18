import XCTest

final class CaptureConfigurationPlannerTests: XCTestCase {
    func testPlansFullDisplayAtNativePixelDimensions() throws {
        let display = CaptureDisplay(
            id: 7,
            name: "Display 1",
            frame: CaptureRect(x: 0, y: 0, width: 1_440, height: 900),
            pixelWidth: 2_880,
            pixelHeight: 1_800
        )

        let plan = try CaptureConfigurationPlanner.plan(
            target: .display(DisplayCaptureTarget(displayID: display.id)),
            catalog: CaptureCatalog(displays: [display], windows: [])
        )

        XCTAssertEqual(plan.filter, .display(displayID: 7))
        XCTAssertNil(plan.sourceRect)
        XCTAssertEqual(plan.outputWidth, 2_880)
        XCTAssertEqual(plan.outputHeight, 1_800)
    }

    func testMapsGlobalRegionIntoDisplayLocalCoordinates() throws {
        let display = CaptureDisplay(
            id: 9,
            name: "Display 2",
            frame: CaptureRect(x: -1_280, y: -200, width: 1_280, height: 800),
            pixelWidth: 2_560,
            pixelHeight: 1_600
        )
        let target = RegionCaptureTarget(
            displayID: display.id,
            rect: CaptureRect(x: -1_180, y: -150, width: 300, height: 200)
        )

        let plan = try CaptureConfigurationPlanner.plan(
            target: .region(target),
            catalog: CaptureCatalog(displays: [display], windows: [])
        )

        XCTAssertEqual(plan.sourceRect, CaptureRect(x: 100, y: 50, width: 300, height: 200))
        XCTAssertEqual(plan.outputWidth, 600)
        XCTAssertEqual(plan.outputHeight, 400)
    }

    func testRejectsRegionCrossingDisplayBoundary() {
        let display = CaptureDisplay(
            id: 4,
            name: "Display 1",
            frame: CaptureRect(x: 0, y: 0, width: 1_000, height: 800),
            pixelWidth: 1_000,
            pixelHeight: 800
        )
        let target = RegionCaptureTarget(
            displayID: display.id,
            rect: CaptureRect(x: 900, y: 100, width: 200, height: 200)
        )

        XCTAssertThrowsError(
            try CaptureConfigurationPlanner.plan(
                target: .region(target),
                catalog: CaptureCatalog(displays: [display], windows: [])
            )
        ) { error in
            XCTAssertEqual(error as? ScreenCaptureError, .regionOutsideDisplay(4))
        }
    }

    func testWindowUsesScaleOfDisplayWithLargestIntersection() throws {
        let standardDisplay = CaptureDisplay(
            id: 1,
            name: "Standard",
            frame: CaptureRect(x: 0, y: 0, width: 1_000, height: 800),
            pixelWidth: 1_000,
            pixelHeight: 800
        )
        let retinaDisplay = CaptureDisplay(
            id: 2,
            name: "Retina",
            frame: CaptureRect(x: 1_000, y: 0, width: 1_000, height: 800),
            pixelWidth: 2_000,
            pixelHeight: 1_600
        )
        let window = CaptureWindow(
            id: 22,
            title: "Editor",
            frame: CaptureRect(x: 900, y: 100, width: 500, height: 300),
            layer: 0,
            applicationName: "Example",
            bundleIdentifier: "com.example.app",
            processID: 42
        )

        let plan = try CaptureConfigurationPlanner.plan(
            target: .window(WindowCaptureTarget(windowID: window.id)),
            catalog: CaptureCatalog(
                displays: [standardDisplay, retinaDisplay],
                windows: [window]
            )
        )

        XCTAssertEqual(plan.outputWidth, 1_000)
        XCTAssertEqual(plan.outputHeight, 600)
    }
}
