import AppKit
import CoreGraphics

/// Converts between AppKit's bottom-left global coordinates and the top-left global coordinate
/// space used by Core Graphics and ScreenCaptureKit.
@MainActor
struct SelectionOverlayCoordinateSpace {
    private let mainDisplayHeight: CGFloat

    init(mainDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height) {
        self.mainDisplayHeight = mainDisplayHeight
    }

    func capturePoint(forAppKitScreenPoint point: CGPoint) -> SelectionPoint {
        SelectionPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    func appKitScreenRect(forCaptureRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func capturePoint(for event: NSEvent, in view: NSView) -> SelectionPoint? {
        guard let window = view.window else { return nil }
        let windowPoint = view.convert(event.locationInWindow, from: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        return capturePoint(forAppKitScreenPoint: screenPoint)
    }

    func localRect(forCaptureRect rect: CGRect, in view: NSView) -> CGRect? {
        guard let window = view.window else { return nil }
        let screenRect = appKitScreenRect(forCaptureRect: rect.standardized)
        let origin = window.convertPoint(fromScreen: screenRect.origin)
        return view.convert(CGRect(origin: origin, size: screenRect.size), from: nil)
    }
}
