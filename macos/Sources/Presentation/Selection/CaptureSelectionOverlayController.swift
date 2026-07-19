import AppKit
import CoreGraphics

/// Presents a native, keyboard-accessible selection surface across every capturable display.
/// Only one selection may be active on an instance at a time.
@MainActor
final class CaptureSelectionOverlayController: NSObject {
    private var machine: CaptureSelectionStateMachine?
    private var panels: [CaptureSelectionOverlayPanel] = []
    private var continuation: CheckedContinuation<CaptureSelectionOutcome, Never>?
    private var lastPointer: SelectionPoint?
    private var keyboardTargetIndex: Int?
    private var keyboardRegionAnchorIsSet = false

    func select(
        mode: CaptureSelectionMode,
        catalog: CaptureCatalog,
        regionPolicy: RegionSelectionPolicy = RegionSelectionPolicy()
    ) async -> CaptureSelectionOutcome {
        guard continuation == nil else {
            return .cancelled(.userCancelled)
        }

        let machine = CaptureSelectionStateMachine(
            mode: mode,
            catalog: catalog,
            regionPolicy: regionPolicy
        )
        if let outcome = machine.outcome {
            return outcome
        }

        self.machine = machine
        keyboardTargetIndex = nil
        keyboardRegionAnchorIsSet = false

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else {
                    finish(.cancelled(.userCancelled))
                    return
                }
                presentPanels(mode: mode, catalog: catalog)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func cancel() {
        guard var machine else { return }
        finish(machine.cancel())
    }

    private func presentPanels(mode: CaptureSelectionMode, catalog: CaptureCatalog) {
        let coordinateSpace = SelectionOverlayCoordinateSpace()
        let screenByDisplayID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                screen.displayID.map { ($0, screen) }
            }
        )

        panels = catalog.displays.compactMap { display in
            guard let screen = screenByDisplayID[display.id] else { return nil }
            let panel = CaptureSelectionOverlayPanel(screen: screen)
            panel.selectionDelegate = self
            let view = CaptureSelectionOverlayView(
                mode: mode,
                catalog: catalog,
                display: display,
                coordinateSpace: coordinateSpace
            )
            view.delegate = self
            panel.contentView = view
            return panel
        }

        guard !panels.isEmpty else {
            finish(.cancelled(.noDisplays))
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        panels.forEach { $0.orderFrontRegardless() }

        let currentMousePoint = coordinateSpace.capturePoint(
            forAppKitScreenPoint: NSEvent.mouseLocation
        )
        let mousePoint =
            SelectionGeometry.display(at: currentMousePoint, in: catalog.displays) == nil
            ? SelectionPoint(catalog.displays[0].frame.cgRect.standardized.center)
            : currentMousePoint
        lastPointer = mousePoint
        machine?.pointerMoved(to: mousePoint)
        updateViews()

        let keyPanel = panel(containing: NSEvent.mouseLocation) ?? panels[0]
        keyPanel.makeKeyAndOrderFront(nil)
    }

    private func finish(_ outcome: CaptureSelectionOutcome) {
        guard let continuation else { return }
        panels.forEach { panel in
            panel.selectionDelegate = nil
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        machine = nil
        lastPointer = nil
        keyboardTargetIndex = nil
        keyboardRegionAnchorIsSet = false
        self.continuation = nil
        continuation.resume(returning: outcome)
    }

    private func panel(containing point: CGPoint) -> CaptureSelectionOverlayPanel? {
        panels.first { $0.frame.contains(point) }
    }

    private func updateViews() {
        guard let state = machine?.state else { return }
        panels.compactMap { $0.contentView as? CaptureSelectionOverlayView }
            .forEach { $0.update(selectionState: state) }
    }

    private func confirmSelection() {
        guard var machine, let point = lastPointer else { return }
        switch machine.mode {
        case .display:
            guard case .hoveringDisplay(.some) = machine.state else { return }
        case .window:
            guard case .hoveringWindow(.some) = machine.state else { return }
        case .region:
            guard case .draggingRegion = machine.state else {
                setRegionAnchor()
                return
            }
        }

        if let outcome = machine.pointerUp(at: point) {
            finish(outcome)
        } else {
            self.machine = machine
            updateViews()
        }
    }

    private func setRegionAnchor() {
        guard var machine, machine.mode == .region, let point = lastPointer else { return }
        if keyboardRegionAnchorIsSet {
            confirmSelection()
            return
        }
        machine.pointerDown(at: point)
        if let outcome = machine.outcome {
            finish(outcome)
            return
        }
        self.machine = machine
        keyboardRegionAnchorIsSet = true
        updateViews()
    }

    private func navigate(_ navigation: SelectionOverlayNavigation, largeStep: Bool) {
        guard let machine else { return }
        switch machine.mode {
        case .display, .window:
            navigateTargets(navigation, machine: machine)
        case .region:
            navigateRegion(navigation, machine: machine, largeStep: largeStep)
        }
    }

    private func navigateTargets(
        _ navigation: SelectionOverlayNavigation,
        machine: CaptureSelectionStateMachine
    ) {
        let rects: [CGRect]
        switch machine.mode {
        case .display:
            rects = machine.catalog.displays.map(\.frame.cgRect)
        case .window:
            rects = machine.catalog.windows.map(\.frame.cgRect)
        case .region:
            return
        }
        guard !rects.isEmpty else { return }

        let nextIndex: Int
        switch navigation {
        case .next:
            nextIndex = ((keyboardTargetIndex ?? -1) + 1) % rects.count
        case .previous:
            nextIndex = ((keyboardTargetIndex ?? 0) - 1 + rects.count) % rects.count
        case .left, .right, .up, .down:
            nextIndex = spatialTargetIndex(
                from: keyboardTargetIndex,
                direction: navigation,
                rects: rects
            )
        }

        keyboardTargetIndex = nextIndex
        let center = rects[nextIndex].standardized.center
        let point = SelectionPoint(center)
        lastPointer = point
        var updatedMachine = machine
        updatedMachine.pointerMoved(to: point)
        self.machine = updatedMachine
        updateViews()
    }

    private func spatialTargetIndex(
        from currentIndex: Int?,
        direction: SelectionOverlayNavigation,
        rects: [CGRect]
    ) -> Int {
        guard let currentIndex else { return 0 }
        let origin = rects[currentIndex].standardized.center
        let candidates = rects.indices.filter { index in
            guard index != currentIndex else { return false }
            let candidate = rects[index].standardized.center
            switch direction {
            case .left: return candidate.x < origin.x
            case .right: return candidate.x > origin.x
            case .up: return candidate.y < origin.y
            case .down: return candidate.y > origin.y
            case .next, .previous: return false
            }
        }
        return candidates.min { lhs, rhs in
            origin.squaredDistance(to: rects[lhs].standardized.center)
                < origin.squaredDistance(to: rects[rhs].standardized.center)
        } ?? currentIndex
    }

    private func navigateRegion(
        _ navigation: SelectionOverlayNavigation,
        machine: CaptureSelectionStateMachine,
        largeStep: Bool
    ) {
        guard navigation != .next, navigation != .previous else { return }
        let initialPoint =
            lastPointer
            ?? machine.catalog.displays[0].frame.cgRect.standardized.center.selectionPoint
        let amount = largeStep ? 10.0 : 1.0
        var next = initialPoint
        switch navigation {
        case .left: next.x -= amount
        case .right: next.x += amount
        case .up: next.y -= amount
        case .down: next.y += amount
        case .next, .previous: break
        }

        lastPointer = next
        var updatedMachine = machine
        if keyboardRegionAnchorIsSet {
            updatedMachine.pointerDragged(to: next)
        }
        self.machine = updatedMachine
        updateViews()
    }
}

@MainActor
extension CaptureSelectionOverlayController: CaptureSelectionOverlayPanelDelegate {
    func selectionPanelDidRequestCancellation(_ panel: CaptureSelectionOverlayPanel) {
        cancel()
    }

    func selectionPanelDidRequestConfirmation(_ panel: CaptureSelectionOverlayPanel) {
        confirmSelection()
    }

    func selectionPanel(
        _ panel: CaptureSelectionOverlayPanel,
        didRequestNavigation navigation: SelectionOverlayNavigation
    ) {
        navigate(navigation, largeStep: NSEvent.modifierFlags.contains(.shift))
    }

    func selectionPanelDidRequestRegionAnchor(_ panel: CaptureSelectionOverlayPanel) {
        setRegionAnchor()
    }
}

@MainActor
extension CaptureSelectionOverlayController: CaptureSelectionOverlayViewDelegate {
    func selectionView(_ view: CaptureSelectionOverlayView, pointerMovedTo point: SelectionPoint) {
        guard var machine else { return }
        lastPointer = point
        machine.pointerMoved(to: point)
        self.machine = machine
        updateViews()
    }

    func selectionView(_ view: CaptureSelectionOverlayView, pointerDownAt point: SelectionPoint) {
        guard var machine else { return }
        lastPointer = point
        machine.pointerDown(at: point)
        self.machine = machine
        keyboardRegionAnchorIsSet = machine.mode == .region
        updateViews()
    }

    func selectionView(_ view: CaptureSelectionOverlayView, pointerDraggedTo point: SelectionPoint)
    {
        guard var machine else { return }
        lastPointer = point
        machine.pointerDragged(to: point)
        self.machine = machine
        updateViews()
    }

    func selectionView(_ view: CaptureSelectionOverlayView, pointerUpAt point: SelectionPoint) {
        guard var machine else { return }
        lastPointer = point
        if let outcome = machine.pointerUp(at: point) {
            finish(outcome)
        } else {
            self.machine = machine
            updateViews()
        }
    }

    func selectionViewDidRequestConfirmation(_ view: CaptureSelectionOverlayView) {
        confirmSelection()
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    var selectionPoint: SelectionPoint { SelectionPoint(self) }

    func squaredDistance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}
