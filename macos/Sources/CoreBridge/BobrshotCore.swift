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
}
