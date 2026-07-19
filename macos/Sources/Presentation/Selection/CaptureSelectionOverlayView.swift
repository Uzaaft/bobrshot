import AppKit

@MainActor
protocol CaptureSelectionOverlayViewDelegate: AnyObject {
    func selectionView(_ view: CaptureSelectionOverlayView, pointerMovedTo point: SelectionPoint)
    func selectionView(_ view: CaptureSelectionOverlayView, pointerDownAt point: SelectionPoint)
    func selectionView(_ view: CaptureSelectionOverlayView, pointerDraggedTo point: SelectionPoint)
    func selectionView(_ view: CaptureSelectionOverlayView, pointerUpAt point: SelectionPoint)
    func selectionViewDidRequestConfirmation(_ view: CaptureSelectionOverlayView)
}

@MainActor
final class CaptureSelectionOverlayView: NSView {
    weak var delegate: (any CaptureSelectionOverlayViewDelegate)?

    private let mode: CaptureSelectionMode
    private let catalog: CaptureCatalog
    private let display: CaptureDisplay
    private let coordinateSpace: SelectionOverlayCoordinateSpace
    private var trackingAreaReference: NSTrackingArea?
    private var selectionState: CaptureSelectionState = .ready

    init(
        mode: CaptureSelectionMode,
        catalog: CaptureCatalog,
        display: CaptureDisplay,
        coordinateSpace: SelectionOverlayCoordinateSpace
    ) {
        self.mode = mode
        self.catalog = catalog
        self.display = display
        self.coordinateSpace = coordinateSpace
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    func update(selectionState: CaptureSelectionState) {
        guard self.selectionState != selectionState else { return }
        self.selectionState = selectionState
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func mouseEntered(with event: NSEvent) {
        movePointer(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        movePointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        movePointer(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = coordinateSpace.capturePoint(for: event, in: self) else { return }
        delegate?.selectionView(self, pointerDownAt: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = coordinateSpace.capturePoint(for: event, in: self) else { return }
        delegate?.selectionView(self, pointerDraggedTo: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard let point = coordinateSpace.capturePoint(for: event, in: self) else { return }
        delegate?.selectionView(self, pointerUpAt: point)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: mode == .region ? .crosshair : .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let dimColor = NSColor.black.withAlphaComponent(contrast ? 0.48 : 0.30)
        let highlight = highlightedCaptureRect.flatMap {
            coordinateSpace.localRect(forCaptureRect: $0, in: self)
        }?.intersection(bounds)

        if let highlight, !highlight.isNull, !highlight.isEmpty {
            let shade = NSBezierPath(rect: bounds)
            shade.appendRect(highlight)
            shade.windingRule = .evenOdd
            dimColor.setFill()
            shade.fill()

            drawSelectionBorder(around: highlight, increasedContrast: contrast)
            if case let .draggingRegion(drag) = selectionState {
                drawRegionDimensions(drag, beside: highlight)
            }
        } else {
            dimColor.setFill()
            bounds.fill()
        }
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        switch mode {
        case .display:
            "Screen capture display selection"
        case .window:
            "Screen capture window selection"
        case .region:
            "Screen capture region selection"
        }
    }

    override func accessibilityValue() -> Any? {
        accessibilitySelectionDescription
    }

    override func accessibilityHelp() -> String? {
        switch mode {
        case .display, .window:
            "Use Tab or the arrow keys to choose a target. Press Return to select it, or Escape to cancel."
        case .region:
            "Press Space to set the first corner, use the arrow keys to size the region, then press Return. Press Escape to cancel."
        }
    }

    override func accessibilityPerformPress() -> Bool {
        delegate?.selectionViewDidRequestConfirmation(self)
        return true
    }

    private func movePointer(with event: NSEvent) {
        guard let point = coordinateSpace.capturePoint(for: event, in: self) else { return }
        delegate?.selectionView(self, pointerMovedTo: point)
    }

    private var highlightedCaptureRect: CGRect? {
        switch selectionState {
        case let .hoveringDisplay(displayID):
            catalog.displays.first(where: { $0.id == displayID })?.frame.cgRect
        case let .hoveringWindow(windowID):
            catalog.windows.first(where: { $0.id == windowID })?.frame.cgRect
        case let .draggingRegion(drag):
            drag.geometry.rect?.cgRect
        case .ready, .finished:
            nil
        }
    }

    private var accessibilitySelectionDescription: String {
        switch selectionState {
        case let .hoveringDisplay(displayID):
            guard let selected = catalog.displays.first(where: { $0.id == displayID }) else {
                return "No display selected"
            }
            return selected.name.isEmpty ? "Display " + String(selected.id) : selected.name
        case let .hoveringWindow(windowID):
            guard let selected = catalog.windows.first(where: { $0.id == windowID }) else {
                return "No window selected"
            }
            let title = selected.title.isEmpty ? "Untitled window" : selected.title
            if let applicationName = selected.applicationName, !applicationName.isEmpty {
                return applicationName + ", " + title
            }
            return title
        case let .draggingRegion(drag):
            guard let rect = drag.geometry.rect else { return "Invalid region" }
            let size = String(
                format: "%.0f by %.0f points",
                rect.width.rounded(),
                rect.height.rounded()
            )
            switch drag.geometry {
            case .valid:
                return size
            case .tooSmall:
                return size + ", too small"
            case .invalid:
                return "Invalid region"
            }
        case .ready:
            return mode == .region ? "No region started" : "No target selected"
        case let .finished(outcome):
            switch outcome {
            case .selected:
                return "Selection complete"
            case .cancelled:
                return "Selection cancelled"
            }
        }
    }

    private func drawSelectionBorder(around rect: CGRect, increasedContrast: Bool) {
        let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        border.lineWidth = increasedContrast ? 3 : 2

        if case let .draggingRegion(drag) = selectionState,
            case .tooSmall = drag.geometry
        {
            border.setLineDash([5, 3], count: 2, phase: 0)
            NSColor.systemOrange.setStroke()
        } else {
            NSColor.controlAccentColor.setStroke()
        }
        border.stroke()
    }

    private func drawRegionDimensions(_ drag: RegionDragSelection, beside rect: CGRect) {
        guard let region = drag.geometry.rect else { return }
        let text = String(
            format: "%.0f × %.0f",
            region.width.rounded(),
            region.height.rounded()
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let bubbleSize = CGSize(width: size.width + 12, height: size.height + 7)
        let preferredY = rect.minY - bubbleSize.height - 6
        let origin = CGPoint(
            x: min(max(rect.minX, bounds.minX + 6), bounds.maxX - bubbleSize.width - 6),
            y: preferredY >= bounds.minY + 6
                ? preferredY : min(rect.maxY + 6, bounds.maxY - bubbleSize.height - 6)
        )
        let bubbleRect = CGRect(origin: origin, size: bubbleSize)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: bubbleRect, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(
            at: CGPoint(x: bubbleRect.minX + 6, y: bubbleRect.minY + 3.5),
            withAttributes: attributes
        )
    }
}
