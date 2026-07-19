import Foundation

enum RecordingVideoCodec: String, Codable, CaseIterable, Sendable {
    case h264
    case hevc
}

struct ScreenRecordingOptions: Codable, Equatable, Sendable {
    var codec: RecordingVideoCodec
    var framesPerSecond: Int
    var videoBitRate: Int?
    var capturesSystemAudio: Bool
    var excludesCurrentProcessAudio: Bool
    var showsCursor: Bool

    init(
        codec: RecordingVideoCodec = .h264,
        framesPerSecond: Int = 60,
        videoBitRate: Int? = nil,
        capturesSystemAudio: Bool = true,
        excludesCurrentProcessAudio: Bool = true,
        showsCursor: Bool = true
    ) {
        self.codec = codec
        self.framesPerSecond = framesPerSecond
        self.videoBitRate = videoBitRate
        self.capturesSystemAudio = capturesSystemAudio
        self.excludesCurrentProcessAudio = excludesCurrentProcessAudio
        self.showsCursor = showsCursor
    }
}

enum ScreenRecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case stopping
    case failed(String)
}

struct ScreenRecordingResult: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
    let videoFrameCount: Int
    let fileSize: Int64
}

enum ScreenRecordingError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case destinationMustBeFileURL
    case destinationAlreadyExists(URL)
    case invalidFrameRate(Int)
    case invalidVideoBitRate(Int)
    case unsupportedDimensions(width: Int, height: Int)
    case contentUnavailable(String)
    case ownWindowCannotBeRecorded
    case writerCreationFailed(String)
    case streamConfigurationFailed(String)
    case streamStartFailed(String)
    case streamStopped(String)
    case writerFailed(String)
    case noVideoFrames
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen recording permission is required to record the screen."
        case .alreadyRecording:
            "A screen recording is already active."
        case .notRecording:
            "There is no active screen recording."
        case .destinationMustBeFileURL:
            "The recording destination must be a local file URL."
        case let .destinationAlreadyExists(url):
            "A file already exists at \(url.path)."
        case let .invalidFrameRate(value):
            "The recording frame rate \(value) is outside the supported range of 1...120."
        case let .invalidVideoBitRate(value):
            "The video bit rate must be positive; received \(value)."
        case let .unsupportedDimensions(width, height):
            "The recording dimensions \(width)x\(height) are not supported by the encoder."
        case let .contentUnavailable(message):
            "Screen content could not be enumerated: \(message)"
        case .ownWindowCannotBeRecorded:
            "Bobrshot windows are excluded from screen recordings."
        case let .writerCreationFailed(message):
            "The recording encoder could not be created: \(message)"
        case let .streamConfigurationFailed(message):
            "The screen stream could not be configured: \(message)"
        case let .streamStartFailed(message):
            "The screen stream could not start: \(message)"
        case let .streamStopped(message):
            "The screen stream stopped unexpectedly: \(message)"
        case let .writerFailed(message):
            "The recording encoder failed: \(message)"
        case .noVideoFrames:
            "The recording ended before a video frame was captured."
        case .cancelled:
            "The screen recording was cancelled."
        }
    }
}
