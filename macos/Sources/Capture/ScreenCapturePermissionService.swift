import CoreGraphics

struct ScreenCapturePermissionService: Sendable {
    func currentStatus() -> ScreenCapturePermission {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Requests access through the system prompt. macOS may require the app to be relaunched
    /// before a newly granted permission is reflected by ScreenCaptureKit.
    func requestAccess() -> ScreenCapturePermission {
        CGRequestScreenCaptureAccess() ? .granted : .denied
    }
}
