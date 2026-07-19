import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case imageEncodingFailed
    case invalidEncodedImage(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            "The captured image could not be encoded as PNG."
        case let .invalidEncodedImage(message):
            "The encoded screenshot is invalid: \(message)"
        }
    }
}

struct ScreenshotWorkflowExportResult: Equatable, Sendable {
    let export: ExportedScreenshot
    let historyEntry: CaptureHistoryEntry
}

@MainActor
final class ScreenshotWorkflowService {
    typealias Clock = @Sendable () -> Date
    typealias Identifier = @Sendable () -> UUID

    private let captureService: ScreenCaptureService
    private let exportService: ScreenshotExportService
    private let historyStore: CaptureHistoryStore
    private let clock: Clock
    private let makeIdentifier: Identifier

    init(
        captureService: ScreenCaptureService = ScreenCaptureService(),
        exportService: ScreenshotExportService = ScreenshotExportService(),
        historyStore: CaptureHistoryStore,
        clock: @escaping Clock = { Date() },
        makeIdentifier: @escaping Identifier = { UUID() }
    ) {
        self.captureService = captureService
        self.exportService = exportService
        self.historyStore = historyStore
        self.clock = clock
        self.makeIdentifier = makeIdentifier
    }

    var permission: ScreenCapturePermission { captureService.permission }

    @discardableResult
    func requestPermission() -> ScreenCapturePermission {
        captureService.requestPermission()
    }

    func catalog() async throws -> CaptureCatalog {
        try await captureService.catalog()
    }

    func capture(
        target: CaptureTarget,
        options: ScreenshotOptions = ScreenshotOptions()
    ) async throws -> ScreenshotDraft {
        let image = try await captureService.captureScreenshot(target: target, options: options)
        let png = try Self.encodePNG(image)
        let descriptor: NativeImageDescriptor
        do {
            descriptor = try NativeImageProbe.inspect(png)
        } catch {
            throw ScreenshotWorkflowError.invalidEncodedImage(error.localizedDescription)
        }
        return ScreenshotDraft(
            id: makeIdentifier(),
            capturedAt: clock(),
            sourcePNG: png,
            editor: AnnotationEditorState(
                document: AnnotationDocument(
                    pixelWidth: descriptor.widthPixels,
                    pixelHeight: descriptor.heightPixels
                )
            )
        )
    }

    func export(
        _ draft: ScreenshotDraft,
        to directory: URL,
        filenamePrefix: String = "Bobrshot",
        optimize: Bool = true,
        directoryAccess: ExportDirectoryAccess = .appOwned
    ) async throws -> ScreenshotWorkflowExportResult {
        let rendered = try draft.renderedPNG()
        let exported = try await exportService.export(
            ScreenshotExportRequest(
                data: rendered,
                directory: directory,
                filenamePrefix: filenamePrefix,
                optimize: optimize,
                directoryAccess: directoryAccess
            )
        )
        let historyEntry = try await historyStore.add(
            exported,
            pixelWidth: draft.pixelWidth,
            pixelHeight: draft.pixelHeight
        )
        return ScreenshotWorkflowExportResult(export: exported, historyEntry: historyEntry)
    }

    func copyImage(_ draft: ScreenshotDraft, to pasteboard: NSPasteboard = .general) throws {
        try ScreenshotClipboard.copyImage(data: draft.renderedPNG(), to: pasteboard)
    }

    func history() async throws -> [CaptureHistoryEntry] {
        try await historyStore.entries()
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw ScreenshotWorkflowError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotWorkflowError.imageEncodingFailed
        }
        return data as Data
    }
}
