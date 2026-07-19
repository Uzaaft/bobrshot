import CoreGraphics
import Foundation

struct SelectionPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

struct RegionSelectionPolicy: Codable, Equatable, Sendable {
    var minimumWidth: Double
    var minimumHeight: Double

    init(minimumWidth: Double = 4, minimumHeight: Double = 4) {
        self.minimumWidth = minimumWidth.isFinite ? max(minimumWidth, 0) : 4
        self.minimumHeight = minimumHeight.isFinite ? max(minimumHeight, 0) : 4
    }
}

enum RegionSelectionGeometry: Codable, Equatable, Sendable {
    case valid(CaptureRect)
    case tooSmall(CaptureRect)
    case invalid

    var rect: CaptureRect? {
        switch self {
        case let .valid(rect), let .tooSmall(rect):
            rect
        case .invalid:
            nil
        }
    }
}

enum SelectionGeometry {
    /// Returns the display containing `point` using half-open bounds. Half-open bounds ensure a
    /// point on a shared display edge belongs to only one display. Input order breaks ties for
    /// overlapping mirrored displays.
    static func display(
        at point: SelectionPoint,
        in displays: [CaptureDisplay]
    ) -> CaptureDisplay? {
        guard point.isFinite else { return nil }

        return displays.first { display in
            containsHalfOpen(display.frame.cgRect.standardized, point: point.cgPoint)
        }
    }

    /// Picks the visible window at a global screen point. Higher window layers win; within one
    /// layer, the catalog's front-to-back order is retained.
    static func window(
        at point: SelectionPoint,
        in catalog: CaptureCatalog
    ) -> CaptureWindow? {
        guard display(at: point, in: catalog.displays) != nil else { return nil }

        return catalog.windows.enumerated()
            .filter { _, window in
                let frame = window.frame.cgRect.standardized
                return isUsable(frame) && containsHalfOpen(frame, point: point.cgPoint)
            }
            .max { lhs, rhs in
                if lhs.element.layer == rhs.element.layer {
                    // Earlier catalog entries are frontmost within a layer.
                    return lhs.offset > rhs.offset
                }
                return lhs.element.layer < rhs.element.layer
            }?
            .element
    }

    /// Normalizes a drag in global screen coordinates and clamps its moving endpoint to the
    /// display where the drag began. A region therefore never spans displays.
    static func region(
        from anchor: SelectionPoint,
        to cursor: SelectionPoint,
        on display: CaptureDisplay,
        policy: RegionSelectionPolicy = RegionSelectionPolicy()
    ) -> RegionSelectionGeometry {
        let frame = display.frame.cgRect.standardized
        guard anchor.isFinite, cursor.isFinite, isUsable(frame),
            containsClosed(frame, point: anchor.cgPoint)
        else {
            return .invalid
        }

        let endpoint = CGPoint(
            x: min(max(cursor.x, frame.minX), frame.maxX),
            y: min(max(cursor.y, frame.minY), frame.maxY)
        )
        let rect = CGRect(
            x: min(anchor.x, endpoint.x),
            y: min(anchor.y, endpoint.y),
            width: abs(endpoint.x - anchor.x),
            height: abs(endpoint.y - anchor.y)
        )
        let captureRect = CaptureRect(rect)

        guard rect.width >= policy.minimumWidth, rect.height >= policy.minimumHeight else {
            return .tooSmall(captureRect)
        }
        return .valid(captureRect)
    }

    private static func containsHalfOpen(_ rect: CGRect, point: CGPoint) -> Bool {
        isUsable(rect)
            && point.x >= rect.minX && point.x < rect.maxX
            && point.y >= rect.minY && point.y < rect.maxY
    }

    private static func containsClosed(_ rect: CGRect, point: CGPoint) -> Bool {
        isUsable(rect)
            && point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}
