import Foundation

enum NativeImageOrientation: UInt8, Equatable, Sendable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8
}

struct NativeImageDescriptor: Equatable, Sendable {
    let format: CoreImageFormat
    let widthPixels: Int
    let heightPixels: Int
    let frameCount: Int
    let orientation: NativeImageOrientation?
    let hasAlpha: Bool?
    let hasColorProfile: Bool
}

enum NativeImageProbeError: Error, Equatable {
    case unsupportedFormat
    case invalidContainer
    case unavailableProperties
    case invalidDimensions
    case invalidOrientation
}

enum NativeImageProbe {
    static func inspect(_ data: Data) throws -> NativeImageDescriptor {
        let inspection: CoreImageInspection
        do {
            inspection = try BobrshotCore.inspectImage(data)
        } catch CoreOptimizationError.unsupportedFormat {
            throw NativeImageProbeError.unsupportedFormat
        } catch CoreOptimizationError.invalidData {
            throw NativeImageProbeError.invalidContainer
        } catch {
            throw NativeImageProbeError.unavailableProperties
        }

        let orientation: NativeImageOrientation?
        if let encodedOrientation = inspection.orientation {
            guard let value = NativeImageOrientation(rawValue: encodedOrientation) else {
                throw NativeImageProbeError.invalidOrientation
            }
            orientation = value
        } else {
            orientation = nil
        }
        guard inspection.widthPixels > 0, inspection.heightPixels > 0 else {
            throw NativeImageProbeError.invalidDimensions
        }
        return NativeImageDescriptor(
            format: inspection.format,
            widthPixels: inspection.widthPixels,
            heightPixels: inspection.heightPixels,
            frameCount: inspection.frameCount,
            orientation: orientation,
            hasAlpha: inspection.hasAlpha,
            hasColorProfile: inspection.hasColorProfile
        )
    }
}
