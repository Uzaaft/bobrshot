import Foundation

@MainActor
final class RecordingWorkflowService {
    private let recordingService: ScreenRecordingService
    private let destinationAllocator: RecordingDestinationAllocator
    private let historyStore: CaptureHistoryStore?
    private var reservation: RecordingDestinationReservation?
    private var activeCodec: RecordingVideoCodec?

    private(set) var latestResult: ScreenRecordingResult?
    private(set) var latestHistoryEntry: CaptureHistoryEntry?

    init(
        recordingService: ScreenRecordingService = ScreenRecordingService(),
        destinationAllocator: RecordingDestinationAllocator = RecordingDestinationAllocator(),
        historyStore: CaptureHistoryStore? = nil
    ) {
        self.recordingService = recordingService
        self.destinationAllocator = destinationAllocator
        self.historyStore = historyStore
    }

    var state: ScreenRecordingState { recordingService.state }
    var destinationURL: URL? { reservation?.destinationURL }

    @discardableResult
    func start(
        target: CaptureTarget,
        in directory: URL,
        filenamePrefix: String = "Bobrshot Recording",
        options: ScreenRecordingOptions = ScreenRecordingOptions()
    ) async throws -> URL {
        guard reservation == nil else {
            throw ScreenRecordingError.alreadyRecording
        }

        let newReservation = try destinationAllocator.allocate(
            in: directory,
            filenamePrefix: filenamePrefix
        )
        reservation = newReservation
        activeCodec = options.codec
        latestResult = nil
        latestHistoryEntry = nil

        do {
            try await recordingService.start(
                target: target,
                destinationURL: newReservation.destinationURL,
                options: options
            )
            return newReservation.destinationURL
        } catch {
            destinationAllocator.release(newReservation)
            try? FileManager.default.removeItem(at: newReservation.destinationURL)
            reservation = nil
            activeCodec = nil
            throw error
        }
    }

    func stop() async throws -> ScreenRecordingResult {
        guard let reservation, let activeCodec else {
            throw ScreenRecordingError.notRecording
        }

        let result: ScreenRecordingResult
        do {
            result = try await recordingService.stop()
        } catch {
            destinationAllocator.release(reservation)
            try? FileManager.default.removeItem(at: reservation.destinationURL)
            self.reservation = nil
            self.activeCodec = nil
            throw error
        }

        destinationAllocator.release(reservation)
        self.reservation = nil
        self.activeCodec = nil
        latestResult = result
        if let historyStore {
            latestHistoryEntry = try await historyStore.add(result, codec: activeCodec)
        }
        return result
    }

    /// Cancels the active recording and releases its reserved filename. Safe to call repeatedly.
    func cancel() {
        recordingService.cancel()
        if let reservation {
            destinationAllocator.release(reservation)
            self.reservation = nil
        }
        activeCodec = nil
    }
}
