import AppKit
import Foundation

enum ScreenshotClipboardError: Error, Equatable, LocalizedError {
    case invalidImageData
    case pasteboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            "The encoded screenshot could not be decoded for the clipboard."
        case .pasteboardWriteFailed:
            "macOS did not accept the screenshot on the clipboard."
        }
    }
}

/// Pasteboard access is main-actor isolated because AppKit pasteboards are UI process state.
@MainActor
enum ScreenshotClipboard {
    static func copyImage(
        data: Data,
        to pasteboard: NSPasteboard = .general
    ) throws {
        guard let image = NSImage(data: data) else {
            throw ScreenshotClipboardError.invalidImageData
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw ScreenshotClipboardError.pasteboardWriteFailed
        }
    }

    /// Copies a file reference, not its pixels. The caller must retain the file for as long as the
    /// pasteboard item may be consumed. Security-scoped access is intentionally the caller's concern.
    static func copyFile(
        at url: URL,
        to pasteboard: NSPasteboard = .general
    ) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else {
            throw ScreenshotClipboardError.pasteboardWriteFailed
        }
    }
}
