import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenCaptureService {
    private let permissionService: ScreenCapturePermissionService
    private let processID: pid_t

    init(
        permissionService: ScreenCapturePermissionService = .init(),
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.permissionService = permissionService
        self.processID = processID
    }

    var permission: ScreenCapturePermission {
        permissionService.currentStatus()
    }

    @discardableResult
    func requestPermission() -> ScreenCapturePermission {
        permissionService.requestAccess()
    }

    func catalog() async throws -> CaptureCatalog {
        guard permission == .granted else {
            throw ScreenCaptureError.permissionDenied
        }

        return Self.makeCatalog(from: try await shareableContent())
    }

    /// Resolves every target against a fresh ScreenCaptureKit content snapshot before capture.
    /// This prevents retaining framework objects across UI selection and capture boundaries.
    func captureScreenshot(
        target: CaptureTarget,
        options: ScreenshotOptions = .init()
    ) async throws -> CGImage {
        guard permission == .granted else {
            throw ScreenCaptureError.permissionDenied
        }

        let content = try await shareableContent()
        let catalog = Self.makeCatalog(from: content)
        let plan = try CaptureConfigurationPlanner.plan(target: target, catalog: catalog)
        let filter = try makeFilter(plan: plan, content: content)
        let configuration = makeConfiguration(filter: filter, plan: plan, options: options)

        return try await captureImage(filter: filter, configuration: configuration)
    }

    private func makeFilter(
        plan: CaptureConfigurationPlan,
        content: SCShareableContent
    ) throws -> SCContentFilter {
        switch plan.filter {
        case let .display(displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenCaptureError.displayUnavailable(displayID)
            }
            let ownApplications = content.applications.filter { $0.processID == processID }
            return SCContentFilter(
                display: display,
                excludingApplications: ownApplications,
                exceptingWindows: []
            )

        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenCaptureError.windowUnavailable(windowID)
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private func makeConfiguration(
        filter: SCContentFilter,
        plan: CaptureConfigurationPlan,
        options: ScreenshotOptions
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let captureSize = plan.sourceRect?.cgRect.size ?? filter.contentRect.size
        let scale = Double(filter.pointPixelScale)
        if scale > 0, scale.isFinite {
            configuration.width = max(Int((captureSize.width * scale).rounded(.up)), 1)
            configuration.height = max(Int((captureSize.height * scale).rounded(.up)), 1)
        } else {
            configuration.width = plan.outputWidth
            configuration.height = plan.outputHeight
        }
        configuration.showsCursor = options.includesCursor
        configuration.ignoreShadowsSingleWindow = !options.includesWindowShadow
        configuration.captureResolution = .best
        if let sourceRect = plan.sourceRect {
            configuration.sourceRect = sourceRect.cgRect
        }
        return configuration
    }

    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                SCShareableContent.getExcludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                ) { content, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let content {
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(
                            throwing: ScreenCaptureError.contentUnavailable(
                                "No content was returned.")
                        )
                    }
                }
            }
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            throw ScreenCaptureError.contentUnavailable(error.localizedDescription)
        }
    }

    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: ScreenCaptureError.captureReturnedNoImage)
                    }
                }
            }
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private static func makeCatalog(from content: SCShareableContent) -> CaptureCatalog {
        let displays = content.displays
            .sorted { $0.displayID < $1.displayID }
            .enumerated()
            .map { index, display in
                CaptureDisplay(
                    id: display.displayID,
                    name: "Display \(index + 1)",
                    frame: CaptureRect(display.frame),
                    pixelWidth: CGDisplayPixelsWide(display.displayID),
                    pixelHeight: CGDisplayPixelsHigh(display.displayID)
                )
            }

        let windows = content.windows
            .filter { $0.windowLayer == 0 && $0.frame.width > 0 && $0.frame.height > 0 }
            .map { window in
                CaptureWindow(
                    id: window.windowID,
                    title: window.title ?? "Untitled Window",
                    frame: CaptureRect(window.frame),
                    layer: window.windowLayer,
                    applicationName: window.owningApplication?.applicationName,
                    bundleIdentifier: window.owningApplication?.bundleIdentifier,
                    processID: window.owningApplication?.processID
                )
            }

        return CaptureCatalog(displays: displays, windows: windows)
    }
}
