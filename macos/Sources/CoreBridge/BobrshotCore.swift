import BobrshotKit
import Foundation

enum CoreImageFormat: Equatable, Sendable {
    case png
    case jpeg
    case gif
    case webP
    case tiff
    case heic
    case heif

    init?(encodedValue: BobrshotImageFormat) {
        switch encodedValue {
        case BobrshotImageFormatPNG:
            self = .png
        case BobrshotImageFormatJPEG:
            self = .jpeg
        case BobrshotImageFormatGIF:
            self = .gif
        case BobrshotImageFormatWebP:
            self = .webP
        case BobrshotImageFormatTIFF:
            self = .tiff
        case BobrshotImageFormatHEIC:
            self = .heic
        case BobrshotImageFormatHEIF:
            self = .heif
        default:
            return nil
        }
    }
}

struct CoreOptimizationOptions: Equatable, Sendable {
    var onlyIfSmaller = true
    var stripMetadata = true
}

struct CoreOptimizationResult: Equatable, Sendable {
    let data: Data
    let format: CoreImageFormat

    var bytesRemoved: Int {
        originalByteCount - data.count
    }

    fileprivate let originalByteCount: Int
}

struct CoreImageInspection: Equatable, Sendable {
    let format: CoreImageFormat
    let widthPixels: Int
    let heightPixels: Int
    let frameCount: Int
    let orientation: UInt8?
    let hasAlpha: Bool?
    let hasColorProfile: Bool
}

enum CoreOptimizationError: Error, Equatable {
    case invalidArgument
    case invalidData
    case unsupportedFormat
    case limitExceeded
    case outOfMemory
    case encodeFailed
    case bufferTooSmall
    case internalFailure(status: BobrshotStatus)
}

struct CoreVersion: CustomStringConvertible, Equatable, Sendable {
    let major: UInt16
    let minor: UInt16
    let patch: UInt16

    var description: String {
        "v\(major).\(minor).\(patch)"
    }
}

enum BobrshotCore {
    static func detectImageFormat(_ data: Data) -> CoreImageFormat? {
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let encodedValue = bobrshot_image_format_detect(bytes.baseAddress, bytes.count)
            return CoreImageFormat(encodedValue: encodedValue)
        }
    }

    static var version: CoreVersion {
        let version = bobrshot_core_version()
        return CoreVersion(
            major: version.major,
            minor: version.minor,
            patch: version.patch
        )
    }

    static func inspectImage(_ data: Data) throws -> CoreImageInspection {
        try data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var descriptor = BobrshotImageDescriptorV1()
            try check(
                bobrshot_image_inspect_v1(
                    bytes.baseAddress,
                    bytes.count,
                    &descriptor
                )
            )
            guard descriptor.struct_size == MemoryLayout<BobrshotImageDescriptorV1>.size,
                let format = CoreImageFormat(encodedValue: descriptor.format),
                descriptor.width > 0,
                descriptor.height > 0,
                descriptor.frame_count > 0
            else {
                throw CoreOptimizationError.internalFailure(status: BobrshotStatusInternal)
            }
            return CoreImageInspection(
                format: format,
                widthPixels: Int(descriptor.width),
                heightPixels: Int(descriptor.height),
                frameCount: Int(descriptor.frame_count),
                orientation: descriptor.orientation == 0 ? nil : descriptor.orientation,
                hasAlpha: descriptor.has_alpha < 0 ? nil : descriptor.has_alpha != 0,
                hasColorProfile: descriptor.has_color_profile != 0
            )
        }
    }

    static func optimizeImage(
        _ data: Data,
        options: CoreOptimizationOptions = CoreOptimizationOptions()
    ) throws -> CoreOptimizationResult {
        try data.withUnsafeBytes { inputBuffer in
            let input = inputBuffer.bindMemory(to: UInt8.self)
            var flags: BobrshotOptimizeFlags = 0
            if options.onlyIfSmaller {
                flags |= BobrshotOptimizeFlagOnlyIfSmaller
            }
            if options.stripMetadata {
                flags |= BobrshotOptimizeFlagStripMetadata
            }

            var request = BobrshotOptimizeRequestV1(
                struct_size: UInt32(MemoryLayout<BobrshotOptimizeRequestV1>.size),
                flags: flags,
                input_bytes: input.baseAddress,
                input_length: input.count,
                output_format: BobrshotImageFormatUnknown,
                quality: 0,
                effort: 0,
                reserved8: 0,
                reserved32: 0
            )
            var outputLength = 0
            var outputFormat = BobrshotImageFormatUnknown
            try check(
                bobrshot_image_optimize_v1(
                    &request,
                    nil,
                    0,
                    &outputLength,
                    &outputFormat
                )
            )
            guard let format = CoreImageFormat(encodedValue: outputFormat) else {
                throw CoreOptimizationError.internalFailure(status: BobrshotStatusInternal)
            }
            if options.onlyIfSmaller, outputLength >= data.count {
                return CoreOptimizationResult(
                    data: data,
                    format: format,
                    originalByteCount: data.count
                )
            }

            var output = Data(count: outputLength)
            try output.withUnsafeMutableBytes { outputBuffer in
                let bytes = outputBuffer.bindMemory(to: UInt8.self)
                try check(
                    bobrshot_image_optimize_v1(
                        &request,
                        bytes.baseAddress,
                        bytes.count,
                        &outputLength,
                        &outputFormat
                    )
                )
            }
            guard outputLength <= output.count else {
                throw CoreOptimizationError.internalFailure(status: BobrshotStatusInternal)
            }
            output.count = outputLength
            return CoreOptimizationResult(
                data: output,
                format: format,
                originalByteCount: data.count
            )
        }
    }

    private static func check(_ status: BobrshotStatus) throws {
        switch status {
        case BobrshotStatusOK:
            return
        case BobrshotStatusInvalidArgument:
            throw CoreOptimizationError.invalidArgument
        case BobrshotStatusInvalidData:
            throw CoreOptimizationError.invalidData
        case BobrshotStatusUnsupportedFormat:
            throw CoreOptimizationError.unsupportedFormat
        case BobrshotStatusLimitExceeded:
            throw CoreOptimizationError.limitExceeded
        case BobrshotStatusOutOfMemory:
            throw CoreOptimizationError.outOfMemory
        case BobrshotStatusEncodeFailed:
            throw CoreOptimizationError.encodeFailed
        case BobrshotStatusBufferTooSmall:
            throw CoreOptimizationError.bufferTooSmall
        default:
            throw CoreOptimizationError.internalFailure(status: status)
        }
    }
}
