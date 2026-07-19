import AppKit

@MainActor
protocol CaptureSelectionOverlayPanelDelegate: AnyObject {
    func selectionPanelDidRequestCancellation(_ panel: CaptureSelectionOverlayPanel)
    func selectionPanelDidRequestConfirmation(_ panel: CaptureSelectionOverlayPanel)
    func selectionPanel(
        _ panel: CaptureSelectionOverlayPanel,
        didRequestNavigation navigation: SelectionOverlayNavigation)
    func selectionPanelDidRequestRegionAnchor(_ panel: CaptureSelectionOverlayPanel)
}

@MainActor
enum SelectionOverlayNavigation {
    case next
    case previous
    case left
    case right
    case up
    case down
}

@MainActor
final class CaptureSelectionOverlayPanel: NSPanel {
    weak var selectionDelegate: (any CaptureSelectionOverlayPanelDelegate)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        sharingType = .none
    }

    override func cancelOperation(_ sender: Any?) {
        selectionDelegate?.selectionPanelDidRequestCancellation(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            selectionDelegate?.selectionPanelDidRequestCancellation(self)
        case 36, 76:
            selectionDelegate?.selectionPanelDidRequestConfirmation(self)
        case 49:
            selectionDelegate?.selectionPanelDidRequestRegionAnchor(self)
        case 48:
            selectionDelegate?.selectionPanel(
                self,
                didRequestNavigation: event.modifierFlags.contains(.shift) ? .previous : .next
            )
        case 123:
            selectionDelegate?.selectionPanel(self, didRequestNavigation: .left)
        case 124:
            selectionDelegate?.selectionPanel(self, didRequestNavigation: .right)
        case 125:
            selectionDelegate?.selectionPanel(self, didRequestNavigation: .down)
        case 126:
            selectionDelegate?.selectionPanel(self, didRequestNavigation: .up)
        default:
            super.keyDown(with: event)
        }
    }
}
