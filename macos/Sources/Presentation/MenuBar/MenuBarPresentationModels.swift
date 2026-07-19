import Foundation

enum MenuBarScreenCapturePermission: Equatable, Sendable {
    case checking
    case notDetermined
    case authorized
    case denied

    var title: String {
        switch self {
        case .checking:
            "Checking Screen Recording Access"
        case .notDetermined:
            "Screen Recording Access Not Requested"
        case .authorized:
            "Screen Recording Access On"
        case .denied:
            "Screen Recording Access Off"
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            "ellipsis.circle"
        case .notDetermined:
            "questionmark.circle"
        case .authorized:
            "checkmark.circle"
        case .denied:
            "exclamationmark.triangle"
        }
    }

    var needsAction: Bool {
        switch self {
        case .notDetermined, .denied:
            true
        case .checking, .authorized:
            false
        }
    }
}

enum MenuBarRecordingStatus: Equatable, Sendable {
    case idle
    case starting
    case recording
    case stopping
    case failed(String)
}

@MainActor
struct MenuBarCaptureActions {
    let captureRegion: () -> Void
    let captureWindow: () -> Void
    let captureDisplay: () -> Void
    let startScreenRecording: () -> Void
    let stopScreenRecording: () -> Void
    let manageScreenCapturePermission: () -> Void
    let openHistory: () -> Void
    let openHistoryEntry: (CaptureHistoryEntry) -> Void
    let openSettings: () -> Void
    let quit: () -> Void
}

enum CaptureHistoryPresentationState: Equatable, Sendable {
    case loading
    case loaded([CaptureHistoryEntry])
    case failed(String)
}

@MainActor
struct CaptureHistoryActions {
    let open: (CaptureHistoryEntry) -> Void
    let revealInFinder: (CaptureHistoryEntry) -> Void
    let copy: (CaptureHistoryEntry) -> Void
    let delete: (CaptureHistoryEntry) -> Void
    let retry: () -> Void
}

extension CaptureHistoryEntry {
    var presentationTitle: String {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        return filename.isEmpty ? "Untitled Capture" : filename
    }

    var presentationKind: String {
        switch kind {
        case let .screenshot(format):
            format.fileExtension.uppercased()
        case let .screenRecording(codec):
            switch codec {
            case .h264:
                "H.264 Video"
            case .hevc:
                "HEVC Video"
            }
        }
    }

    var presentationSystemImage: String {
        switch kind {
        case .screenshot:
            "photo"
        case .screenRecording:
            "video"
        }
    }

    var presentationDimensions: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    var accessibilityDescription: String {
        var components = [presentationKind]
        if let presentationDimensions {
            components.append(presentationDimensions)
        }
        components.append(
            ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        return components.joined(separator: ", ")
    }
}
