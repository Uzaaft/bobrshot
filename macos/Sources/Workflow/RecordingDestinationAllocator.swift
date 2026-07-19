import Darwin
import Foundation

struct RecordingDestinationReservation: Equatable, Sendable {
    let destinationURL: URL
    fileprivate let reservationURL: URL
}

enum RecordingDestinationError: Error, Equatable, LocalizedError, Sendable {
    case directoryMustBeFileURL
    case cannotCreateDirectory(URL, String)
    case cannotReserveDestination(String)
    case exhaustedFilenameAttempts

    var errorDescription: String? {
        switch self {
        case .directoryMustBeFileURL:
            "The recording directory must be a local file URL."
        case let .cannotCreateDirectory(url, message):
            "The recording directory could not be created at \(url.path): \(message)"
        case let .cannotReserveDestination(message):
            "A recording destination could not be reserved: \(message)"
        case .exhaustedFilenameAttempts:
            "A unique recording filename could not be allocated."
        }
    }
}

/// Allocates a friendly, collision-resistant movie URL and holds an atomic sibling reservation.
///
/// The reservation coordinates concurrent Bobrshot processes without placing a file at the movie
/// URL, which AVAssetWriter requires to remain absent. The recorder performs a second existence
/// check before creating the movie, so unrelated writers are also refused rather than overwritten.
struct RecordingDestinationAllocator: Sendable {
    typealias Clock = @Sendable () -> Date
    typealias Identifier = @Sendable () -> UUID

    private let clock: Clock
    private let makeIdentifier: Identifier
    private let maximumAttempts: Int

    init(
        clock: @escaping Clock = { Date() },
        makeIdentifier: @escaping Identifier = { UUID() },
        maximumAttempts: Int = 32
    ) {
        self.clock = clock
        self.makeIdentifier = makeIdentifier
        self.maximumAttempts = max(maximumAttempts, 1)
    }

    func allocate(
        in directory: URL,
        filenamePrefix: String = "Bobrshot Recording"
    ) throws -> RecordingDestinationReservation {
        guard directory.isFileURL else {
            throw RecordingDestinationError.directoryMustBeFileURL
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw RecordingDestinationError.cannotCreateDirectory(
                directory,
                error.localizedDescription
            )
        }

        let prefix = Self.sanitizedPrefix(filenamePrefix)
        let timestamp = Self.filenameTimestamp(clock())

        for _ in 0..<maximumAttempts {
            let identifier = makeIdentifier().uuidString.lowercased()
            let destinationURL =
                directory
                .appendingPathComponent("\(prefix) \(timestamp) \(identifier)")
                .appendingPathExtension("mov")
            let reservationURL = directory.appendingPathComponent(
                ".\(destinationURL.lastPathComponent).bobrshot-reservation"
            )

            guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
                continue
            }
            guard try createReservation(at: reservationURL) else {
                continue
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: reservationURL)
                continue
            }
            return RecordingDestinationReservation(
                destinationURL: destinationURL,
                reservationURL: reservationURL
            )
        }

        throw RecordingDestinationError.exhaustedFilenameAttempts
    }

    func release(_ reservation: RecordingDestinationReservation) {
        try? FileManager.default.removeItem(at: reservation.reservationURL)
    }

    private func createReservation(at url: URL) throws -> Bool {
        let descriptor = open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            if errno == EEXIST { return false }
            throw RecordingDestinationError.cannotReserveDestination(
                String(cString: strerror(errno))
            )
        }
        close(descriptor)
        return true
    }

    private static func sanitizedPrefix(_ prefix: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = prefix.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Bobrshot Recording" : String(sanitized.prefix(80))
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        guard let utc = TimeZone(secondsFromGMT: 0) else { return "unknown-date" }
        let components = Calendar(identifier: .gregorian).dateComponents(in: utc, from: date)
        return String(
            format: "%04d-%02d-%02d at %02d.%02d.%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
