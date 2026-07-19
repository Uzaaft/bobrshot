import Foundation

enum CaptureSelectionMode: String, Codable, Equatable, Sendable {
    case display
    case window
    case region
}

enum CaptureSelectionCancelReason: String, Codable, Equatable, Sendable {
    case userCancelled
    case noDisplays
    case pointerOutsideDisplays
    case noTargetAtPoint
    case regionTooSmall
    case invalidRegion
}

enum CaptureSelectionOutcome: Codable, Equatable, Sendable {
    case selected(CaptureTarget)
    case cancelled(CaptureSelectionCancelReason)
}

struct RegionDragSelection: Codable, Equatable, Sendable {
    let displayID: UInt32
    let anchor: SelectionPoint
    let cursor: SelectionPoint
    let geometry: RegionSelectionGeometry
}

enum CaptureSelectionState: Codable, Equatable, Sendable {
    case ready
    case hoveringDisplay(UInt32?)
    case hoveringWindow(UInt32?)
    case draggingRegion(RegionDragSelection)
    case finished(CaptureSelectionOutcome)
}

/// A UI-independent reducer for a single capture-selection interaction.
struct CaptureSelectionStateMachine: Sendable {
    let mode: CaptureSelectionMode
    let catalog: CaptureCatalog
    let regionPolicy: RegionSelectionPolicy
    private(set) var state: CaptureSelectionState

    init(
        mode: CaptureSelectionMode,
        catalog: CaptureCatalog,
        regionPolicy: RegionSelectionPolicy = RegionSelectionPolicy()
    ) {
        self.mode = mode
        self.catalog = catalog
        self.regionPolicy = regionPolicy
        state = catalog.displays.isEmpty ? .finished(.cancelled(.noDisplays)) : .ready
    }

    mutating func pointerMoved(to point: SelectionPoint) {
        guard !isFinished, !isDraggingRegion else { return }

        switch mode {
        case .display:
            state = .hoveringDisplay(SelectionGeometry.display(at: point, in: catalog.displays)?.id)
        case .window:
            state = .hoveringWindow(SelectionGeometry.window(at: point, in: catalog)?.id)
        case .region:
            break
        }
    }

    mutating func pointerDown(at point: SelectionPoint) {
        guard !isFinished else { return }

        switch mode {
        case .display, .window:
            pointerMoved(to: point)
        case .region:
            guard let display = SelectionGeometry.display(at: point, in: catalog.displays) else {
                state = .finished(.cancelled(.pointerOutsideDisplays))
                return
            }
            state = .draggingRegion(
                RegionDragSelection(
                    displayID: display.id,
                    anchor: point,
                    cursor: point,
                    geometry: .tooSmall(CaptureRect(x: point.x, y: point.y, width: 0, height: 0))
                )
            )
        }
    }

    mutating func pointerDragged(to point: SelectionPoint) {
        guard case let .draggingRegion(drag) = state,
            let display = catalog.displays.first(where: { $0.id == drag.displayID })
        else {
            return
        }

        state = .draggingRegion(
            RegionDragSelection(
                displayID: display.id,
                anchor: drag.anchor,
                cursor: point,
                geometry: SelectionGeometry.region(
                    from: drag.anchor,
                    to: point,
                    on: display,
                    policy: regionPolicy
                )
            )
        )
    }

    @discardableResult
    mutating func pointerUp(at point: SelectionPoint) -> CaptureSelectionOutcome? {
        guard !isFinished else { return outcome }

        switch mode {
        case .display:
            guard let display = SelectionGeometry.display(at: point, in: catalog.displays) else {
                return finish(.cancelled(.pointerOutsideDisplays))
            }
            return finish(.selected(.display(DisplayCaptureTarget(displayID: display.id))))

        case .window:
            guard let window = SelectionGeometry.window(at: point, in: catalog) else {
                return finish(.cancelled(.noTargetAtPoint))
            }
            return finish(.selected(.window(WindowCaptureTarget(windowID: window.id))))

        case .region:
            pointerDragged(to: point)
            guard case let .draggingRegion(drag) = state else {
                return finish(.cancelled(.invalidRegion))
            }
            switch drag.geometry {
            case let .valid(rect):
                return finish(
                    .selected(.region(RegionCaptureTarget(displayID: drag.displayID, rect: rect)))
                )
            case .tooSmall:
                return finish(.cancelled(.regionTooSmall))
            case .invalid:
                return finish(.cancelled(.invalidRegion))
            }
        }
    }

    @discardableResult
    mutating func cancel(
        reason: CaptureSelectionCancelReason = .userCancelled
    ) -> CaptureSelectionOutcome {
        if let outcome { return outcome }
        return finish(.cancelled(reason))
    }

    var outcome: CaptureSelectionOutcome? {
        guard case let .finished(outcome) = state else { return nil }
        return outcome
    }

    private var isFinished: Bool {
        outcome != nil
    }

    private var isDraggingRegion: Bool {
        if case .draggingRegion = state { return true }
        return false
    }

    @discardableResult
    private mutating func finish(_ outcome: CaptureSelectionOutcome) -> CaptureSelectionOutcome {
        state = .finished(outcome)
        return outcome
    }
}
