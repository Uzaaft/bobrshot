import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenRecordingService {
    private let permissionService: ScreenCapturePermissionService
    private let processID: pid_t
    private var session: ScreenRecordingSession?

    private(set) var state: ScreenRecordingState = .idle

    init(
        permissionService: ScreenCapturePermissionService = .init(),
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.permissionService = permissionService
        self.processID = processID
    }

    func start(
        target: CaptureTarget,
        destinationURL: URL,
        options: ScreenRecordingOptions = .init()
    ) async throws {
        guard session == nil else { throw ScreenRecordingError.alreadyRecording }
        guard permissionService.currentStatus() == .granted else {
            throw ScreenRecordingError.permissionDenied
        }
        guard destinationURL.isFileURL else {
            throw ScreenRecordingError.destinationMustBeFileURL
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw ScreenRecordingError.destinationAlreadyExists(destinationURL)
        }

        state = .starting
        do {
            let content = try await shareableContent()
            let catalog = Self.makeCatalog(from: content)
            let plan = try RecordingConfigurationPlanner.plan(
                target: target,
                catalog: catalog,
                options: options
            )
            let filter = try makeFilter(
                plan: plan.capture,
                content: content,
                target: target
            )
            let configuration = makeStreamConfiguration(plan: plan, options: options)
            let newSession = try ScreenRecordingSession(
                filter: filter,
                configuration: configuration,
                plan: plan,
                options: options,
                destinationURL: destinationURL
            )
            session = newSession
            try await newSession.start()
            state = .recording
        } catch {
            session?.cancel()
            session = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() async throws -> ScreenRecordingResult {
        guard let session else { throw ScreenRecordingError.notRecording }
        state = .stopping
        do {
            let result = try await session.stop()
            self.session = nil
            state = .idle
            return result
        } catch {
            self.session = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Cancels capture and removes the incomplete file. It is safe to call repeatedly.
    func cancel() {
        session?.cancel()
        session = nil
        state = .idle
    }

    private func makeFilter(
        plan: CaptureConfigurationPlan,
        content: SCShareableContent,
        target: CaptureTarget
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
            if window.owningApplication?.processID == processID {
                throw ScreenRecordingError.ownWindowCannotBeRecorded
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private func makeStreamConfiguration(
        plan: RecordingConfigurationPlan,
        options: ScreenRecordingOptions
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = plan.width
        configuration.height = plan.height
        configuration.minimumFrameInterval = CMTime(
            value: 1, timescale: CMTimeScale(plan.framesPerSecond))
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = options.showsCursor
        configuration.capturesAudio = options.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = options.excludesCurrentProcessAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        if let sourceRect = plan.capture.sourceRect {
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
                            throwing: ScreenRecordingError.contentUnavailable(
                                "No content was returned."
                            )
                        )
                    }
                }
            }
        } catch let error as ScreenRecordingError {
            throw error
        } catch {
            throw ScreenRecordingError.contentUnavailable(error.localizedDescription)
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

private final class ScreenRecordingSession: NSObject, @unchecked Sendable {
    private enum State {
        case prepared
        case starting
        case recording
        case stopping
        case stopped
        case cancelled
        case failed
    }

    private let queue = DispatchQueue(label: "app.bobrshot.recording.session", qos: .userInitiated)
    private var stream: SCStream?
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let destinationURL: URL

    // All mutable properties below are confined to `queue`.
    private var state: State = .prepared
    private var sessionStartTime: CMTime?
    private var lastVideoTime: CMTime?
    private var videoFrameCount = 0
    private var terminalError: ScreenRecordingError?

    init(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        plan: RecordingConfigurationPlan,
        options: ScreenRecordingOptions,
        destinationURL: URL
    ) throws {
        self.destinationURL = destinationURL
        do {
            writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        } catch {
            throw ScreenRecordingError.writerCreationFailed(error.localizedDescription)
        }

        let codec: AVVideoCodecType = options.codec == .hevc ? .hevc : .h264
        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: plan.width,
                AVVideoHeightKey: plan.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: plan.videoBitRate,
                    AVVideoExpectedSourceFrameRateKey: plan.framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: plan.framesPerSecond * 2,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ]
        )
        videoInput.expectsMediaDataInRealTime = true

        if options.capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000,
                ]
            )
            input.expectsMediaDataInRealTime = true
            audioInput = input
        } else {
            audioInput = nil
        }

        guard writer.canAdd(videoInput) else {
            throw ScreenRecordingError.writerCreationFailed("The video input is not supported.")
        }
        writer.add(videoInput)
        if let audioInput {
            guard writer.canAdd(audioInput) else {
                throw ScreenRecordingError.writerCreationFailed("The audio input is not supported.")
            }
            writer.add(audioInput)
        }

        super.init()
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                guard let stream else {
                    continuation.resume(
                        throwing: ScreenRecordingError.streamConfigurationFailed(
                            "The capture stream was not initialized."
                        )
                    )
                    return
                }
                guard state == .prepared else {
                    continuation.resume(throwing: ScreenRecordingError.alreadyRecording)
                    return
                }
                do {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                    if audioInput != nil {
                        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                    }
                } catch {
                    state = .failed
                    continuation.resume(
                        throwing: ScreenRecordingError.streamConfigurationFailed(
                            error.localizedDescription
                        )
                    )
                    return
                }
                guard writer.startWriting() else {
                    state = .failed
                    continuation.resume(throwing: writerError())
                    return
                }
                state = .starting
                stream.startCapture { [weak self] error in
                    guard let self else { return }
                    queue.async { [self] in
                        guard state != .cancelled else {
                            continuation.resume(throwing: ScreenRecordingError.cancelled)
                            return
                        }
                        if let error {
                            state = .failed
                            let startError = ScreenRecordingError.streamStartFailed(
                                error.localizedDescription
                            )
                            terminalError = startError
                            writer.cancelWriting()
                            continuation.resume(throwing: startError)
                        } else {
                            state = .recording
                            continuation.resume(returning: ())
                        }
                    }
                }
            }
        }
    }

    func stop() async throws -> ScreenRecordingResult {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ScreenRecordingResult, any Error>) in
            queue.async { [self] in
                guard let stream else {
                    continuation.resume(throwing: ScreenRecordingError.notRecording)
                    return
                }
                if state == .failed {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: destinationURL)
                    continuation.resume(throwing: terminalError ?? writerError())
                    return
                }
                guard state == .recording || state == .starting else {
                    continuation.resume(throwing: ScreenRecordingError.notRecording)
                    return
                }
                state = .stopping
                stream.stopCapture { [weak self] error in
                    guard let self else { return }
                    queue.async { [self] in
                        if let error {
                            state = .failed
                            let stopError = ScreenRecordingError.streamStopped(
                                error.localizedDescription
                            )
                            terminalError = stopError
                            writer.cancelWriting()
                            continuation.resume(throwing: stopError)
                            return
                        }
                        finishWriting(continuation: continuation)
                    }
                }
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            guard state != .cancelled, state != .stopped else { return }
            state = .cancelled
            stream?.stopCapture { _ in }
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    private func finishWriting(
        continuation: CheckedContinuation<ScreenRecordingResult, any Error>
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard videoFrameCount > 0, let startTime = sessionStartTime else {
            state = .failed
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destinationURL)
            continuation.resume(throwing: ScreenRecordingError.noVideoFrames)
            return
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            queue.async { [self] in
                guard self.writer.status == .completed else {
                    self.state = .failed
                    continuation.resume(throwing: self.writerError())
                    return
                }
                self.state = .stopped
                let endTime = self.lastVideoTime ?? startTime
                let duration = max(CMTimeGetSeconds(endTime - startTime), 0)
                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: self.destinationURL.path
                )
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                continuation.resume(
                    returning: ScreenRecordingResult(
                        url: self.destinationURL,
                        duration: duration,
                        videoFrameCount: self.videoFrameCount,
                        fileSize: size
                    )
                )
            }
        }
    }

    private func writerError() -> ScreenRecordingError {
        ScreenRecordingError.writerFailed(
            writer.error?.localizedDescription ?? "The encoder returned an unknown error."
        )
    }
}

extension ScreenRecordingSession: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .recording || state == .stopping else { return }
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else { return }

        switch outputType {
        case .screen:
            guard Self.isCompleteScreenFrame(sampleBuffer) else { return }
            let timestamp = sampleBuffer.presentationTimeStamp
            if sessionStartTime == nil {
                writer.startSession(atSourceTime: timestamp)
                sessionStartTime = timestamp
            }
            guard videoInput.isReadyForMoreMediaData else { return }
            if videoInput.append(sampleBuffer) {
                videoFrameCount += 1
                lastVideoTime = timestamp
            }

        case .audio:
            guard sessionStartTime != nil, let audioInput,
                audioInput.isReadyForMoreMediaData
            else { return }
            _ = audioInput.append(sampleBuffer)

        case .microphone:
            break

        @unknown default:
            break
        }

        if writer.status == .failed {
            state = .failed
            terminalError = writerError()
            stream.stopCapture { _ in }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        queue.async { [self] in
            guard state != .stopping, state != .stopped, state != .cancelled else { return }
            state = .failed
            terminalError = .streamStopped(error.localizedDescription)
            writer.cancelWriting()
        }
    }

    private static func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let statusValue = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusValue)
        else {
            return false
        }
        return status == .complete
    }
}
