import CoreGraphics
import Foundation

/// A transport-safe rectangle expressed in the global macOS screen coordinate space.
struct CaptureRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct CaptureDisplay: Identifiable, Codable, Hashable, Sendable {
    let id: UInt32
    let name: String
    let frame: CaptureRect
    let pixelWidth: Int
    let pixelHeight: Int
}

struct CaptureWindow: Identifiable, Codable, Hashable, Sendable {
    let id: UInt32
    let title: String
    let frame: CaptureRect
    let layer: Int
    let applicationName: String?
    let bundleIdentifier: String?
    let processID: Int32?
}

struct DisplayCaptureTarget: Codable, Hashable, Sendable {
    let displayID: UInt32
}

struct WindowCaptureTarget: Codable, Hashable, Sendable {
    let windowID: UInt32
}

/// Regions intentionally belong to exactly one display. Multi-display region capture can be
/// introduced later without making the common path depend on display-unaware APIs.
struct RegionCaptureTarget: Codable, Hashable, Sendable {
    let displayID: UInt32
    let rect: CaptureRect
}

enum CaptureTarget: Codable, Hashable, Sendable {
    case display(DisplayCaptureTarget)
    case window(WindowCaptureTarget)
    case region(RegionCaptureTarget)
}

struct CaptureCatalog: Codable, Equatable, Sendable {
    let displays: [CaptureDisplay]
    let windows: [CaptureWindow]
}

struct ScreenshotOptions: Codable, Equatable, Sendable {
    var includesCursor: Bool
    var includesWindowShadow: Bool

    init(includesCursor: Bool = true, includesWindowShadow: Bool = true) {
        self.includesCursor = includesCursor
        self.includesWindowShadow = includesWindowShadow
    }
}

enum ScreenCapturePermission: String, Codable, Sendable {
    case granted
    case denied
}

enum ScreenCaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case contentUnavailable(String)
    case noDisplays
    case displayUnavailable(UInt32)
    case windowUnavailable(UInt32)
    case invalidRegion
    case regionOutsideDisplay(UInt32)
    case captureFailed(String)
    case captureReturnedNoImage

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen recording permission is required to capture the screen."
        case let .contentUnavailable(message):
            "Screen content could not be enumerated: \(message)"
        case .noDisplays:
            "No capturable displays are available."
        case let .displayUnavailable(id):
            "Display \(id) is no longer available."
        case let .windowUnavailable(id):
            "Window \(id) is no longer available."
        case .invalidRegion:
            "The selected capture region is empty or invalid."
        case let .regionOutsideDisplay(id):
            "The selected region is not fully contained by display \(id)."
        case let .captureFailed(message):
            "The screenshot could not be captured: \(message)"
        case .captureReturnedNoImage:
            "ScreenCaptureKit completed without returning an image."
        }
    }
}
