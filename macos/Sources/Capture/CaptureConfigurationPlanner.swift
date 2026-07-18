import CoreGraphics
import Foundation

enum CaptureFilterPlan: Equatable, Sendable {
    case display(displayID: UInt32)
    case window(windowID: UInt32)
}

struct CaptureConfigurationPlan: Equatable, Sendable {
    let filter: CaptureFilterPlan
    let sourceRect: CaptureRect?
    let outputWidth: Int
    let outputHeight: Int
}

enum CaptureConfigurationPlanner {
    static func plan(
        target: CaptureTarget,
        catalog: CaptureCatalog
    ) throws -> CaptureConfigurationPlan {
        switch target {
        case let .display(target):
            guard let display = catalog.displays.first(where: { $0.id == target.displayID }) else {
                throw ScreenCaptureError.displayUnavailable(target.displayID)
            }

            return CaptureConfigurationPlan(
                filter: .display(displayID: display.id),
                sourceRect: nil,
                outputWidth: max(display.pixelWidth, 1),
                outputHeight: max(display.pixelHeight, 1)
            )

        case let .window(target):
            guard let window = catalog.windows.first(where: { $0.id == target.windowID }) else {
                throw ScreenCaptureError.windowUnavailable(target.windowID)
            }

            let scale = scaleForWindow(window.frame.cgRect, displays: catalog.displays)
            return CaptureConfigurationPlan(
                filter: .window(windowID: window.id),
                sourceRect: nil,
                outputWidth: pixelLength(window.frame.width, scale: scale),
                outputHeight: pixelLength(window.frame.height, scale: scale)
            )

        case let .region(target):
            guard let display = catalog.displays.first(where: { $0.id == target.displayID }) else {
                throw ScreenCaptureError.displayUnavailable(target.displayID)
            }

            let rect = target.rect.cgRect.standardized
            guard rect.width.isFinite, rect.height.isFinite,
                rect.origin.x.isFinite, rect.origin.y.isFinite,
                rect.width > 0, rect.height > 0
            else {
                throw ScreenCaptureError.invalidRegion
            }

            let displayFrame = display.frame.cgRect.standardized
            guard displayFrame.contains(rect) else {
                throw ScreenCaptureError.regionOutsideDisplay(display.id)
            }

            let scaleX = scale(logical: displayFrame.width, pixels: display.pixelWidth)
            let scaleY = scale(logical: displayFrame.height, pixels: display.pixelHeight)
            let localRect = CGRect(
                x: rect.minX - displayFrame.minX,
                y: rect.minY - displayFrame.minY,
                width: rect.width,
                height: rect.height
            )

            return CaptureConfigurationPlan(
                filter: .display(displayID: display.id),
                sourceRect: CaptureRect(localRect),
                outputWidth: pixelLength(rect.width, scale: scaleX),
                outputHeight: pixelLength(rect.height, scale: scaleY)
            )
        }
    }

    private static func scaleForWindow(_ rect: CGRect, displays: [CaptureDisplay]) -> Double {
        let display = displays.max { lhs, rhs in
            lhs.frame.cgRect.intersection(rect).area < rhs.frame.cgRect.intersection(rect).area
        }
        guard let display else { return 1 }
        return scale(logical: display.frame.width, pixels: display.pixelWidth)
    }

    private static func scale(logical: Double, pixels: Int) -> Double {
        guard logical > 0, pixels > 0 else { return 1 }
        return Double(pixels) / logical
    }

    private static func pixelLength(_ points: Double, scale: Double) -> Int {
        max(Int((points * scale).rounded(.up)), 1)
    }
}

private extension CGRect {
    var area: Double {
        guard !isNull, !isInfinite else { return 0 }
        return width * height
    }
}
