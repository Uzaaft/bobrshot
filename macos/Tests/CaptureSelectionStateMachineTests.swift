import CoreGraphics
import XCTest

final class CaptureSelectionStateMachineTests: XCTestCase {
    func testDisplayHitTestingUsesHalfOpenSharedEdge() {
        let displays = [
            display(id: 1, x: -100, y: 0, width: 100, height: 100),
            display(id: 2, x: 0, y: 0, width: 100, height: 100),
        ]

        XCTAssertEqual(
            SelectionGeometry.display(at: SelectionPoint(x: -0.1, y: 50), in: displays)?.id, 1)
        XCTAssertEqual(
            SelectionGeometry.display(at: SelectionPoint(x: 0, y: 50), in: displays)?.id, 2)
    }

    func testWindowHitTestingUsesLayerThenCatalogOrder() {
        let catalog = CaptureCatalog(
            displays: [display(id: 1, x: 0, y: 0, width: 500, height: 500)],
            windows: [
                window(id: 10, layer: 0),
                window(id: 11, layer: 0),
                window(id: 12, layer: 3),
            ]
        )

        XCTAssertEqual(
            SelectionGeometry.window(at: SelectionPoint(x: 50, y: 50), in: catalog)?.id, 12)

        let normalWindows = CaptureCatalog(
            displays: catalog.displays, windows: Array(catalog.windows.prefix(2)))
        XCTAssertEqual(
            SelectionGeometry.window(at: SelectionPoint(x: 50, y: 50), in: normalWindows)?.id, 10)
    }

    func testRegionNormalizesReverseDragAndClampsToStartingDisplay() {
        let selectedDisplay = display(id: 1, x: -200, y: 20, width: 200, height: 100)

        let geometry = SelectionGeometry.region(
            from: SelectionPoint(x: -50, y: 80),
            to: SelectionPoint(x: -400, y: -100),
            on: selectedDisplay
        )

        XCTAssertEqual(
            geometry,
            .valid(CaptureRect(x: -200, y: 20, width: 150, height: 60))
        )
    }

    func testRegionRejectsSelectionBelowPolicyMinimum() {
        let selectedDisplay = display(id: 1, x: 0, y: 0, width: 100, height: 100)

        let geometry = SelectionGeometry.region(
            from: SelectionPoint(x: 10, y: 10),
            to: SelectionPoint(x: 14, y: 17),
            on: selectedDisplay,
            policy: RegionSelectionPolicy(minimumWidth: 5, minimumHeight: 5)
        )

        XCTAssertEqual(
            geometry,
            .tooSmall(CaptureRect(x: 10, y: 10, width: 4, height: 7))
        )
    }

    func testRegionStateMachineProducesDisplayBoundGlobalTarget() {
        let catalog = CaptureCatalog(
            displays: [
                display(id: 1, x: 0, y: 0, width: 100, height: 100),
                display(id: 2, x: 100, y: 0, width: 100, height: 100),
            ],
            windows: []
        )
        var machine = CaptureSelectionStateMachine(mode: .region, catalog: catalog)

        machine.pointerDown(at: SelectionPoint(x: 80, y: 20))
        machine.pointerDragged(to: SelectionPoint(x: 150, y: 70))
        let outcome = machine.pointerUp(at: SelectionPoint(x: 150, y: 70))

        XCTAssertEqual(
            outcome,
            .selected(
                .region(
                    RegionCaptureTarget(
                        displayID: 1,
                        rect: CaptureRect(x: 80, y: 20, width: 20, height: 50)
                    )
                )
            )
        )
    }

    func testTooSmallRegionFinishesWithExplicitCancellation() {
        let catalog = CaptureCatalog(
            displays: [display(id: 1, x: 0, y: 0, width: 100, height: 100)],
            windows: []
        )
        var machine = CaptureSelectionStateMachine(mode: .region, catalog: catalog)

        machine.pointerDown(at: SelectionPoint(x: 10, y: 10))
        let outcome = machine.pointerUp(at: SelectionPoint(x: 11, y: 12))

        XCTAssertEqual(outcome, .cancelled(.regionTooSmall))
        XCTAssertEqual(machine.state, .finished(.cancelled(.regionTooSmall)))
    }

    func testEmptyCatalogStartsFinished() {
        let machine = CaptureSelectionStateMachine(
            mode: .display,
            catalog: CaptureCatalog(displays: [], windows: [])
        )

        XCTAssertEqual(machine.outcome, .cancelled(.noDisplays))
    }

    private func display(
        id: UInt32,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> CaptureDisplay {
        CaptureDisplay(
            id: id,
            name: "Display \(id)",
            frame: CaptureRect(x: x, y: y, width: width, height: height),
            pixelWidth: Int(width * 2),
            pixelHeight: Int(height * 2)
        )
    }

    private func window(id: UInt32, layer: Int) -> CaptureWindow {
        CaptureWindow(
            id: id,
            title: "Window \(id)",
            frame: CaptureRect(x: 0, y: 0, width: 100, height: 100),
            layer: layer,
            applicationName: "Fixture",
            bundleIdentifier: "example.fixture",
            processID: 1
        )
    }
}
