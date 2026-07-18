import CoreFoundation
import Foundation
import ImageIO

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
        guard let format = BobrshotCore.detectImageFormat(data) else {
            throw NativeImageProbeError.unsupportedFormat
        }

        return try data.withUnsafeBytes {
            (buffer: UnsafeRawBufferPointer) throws -> NativeImageDescriptor in
            let bytes = buffer.bindMemory(to: UInt8.self)
            guard let baseAddress = bytes.baseAddress,
                let sourceData = CFDataCreateWithBytesNoCopy(
                    kCFAllocatorDefault,
                    baseAddress,
                    bytes.count,
                    kCFAllocatorNull
                ),
                let source = CGImageSourceCreateWithData(sourceData, nil),
                CGImageSourceGetStatus(source) == .statusComplete
            else {
                throw NativeImageProbeError.invalidContainer
            }

            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 0,
                CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            else {
                throw NativeImageProbeError.unavailableProperties
            }

            guard let widthPixels = integer(in: properties, for: kCGImagePropertyPixelWidth),
                let heightPixels = integer(in: properties, for: kCGImagePropertyPixelHeight),
                widthPixels > 0,
                heightPixels > 0,
                !widthPixels.multipliedReportingOverflow(by: heightPixels).overflow
            else {
                throw NativeImageProbeError.invalidDimensions
            }

            return NativeImageDescriptor(
                format: format,
                widthPixels: widthPixels,
                heightPixels: heightPixels,
                frameCount: frameCount,
                orientation: try orientation(in: properties),
                hasAlpha: boolean(in: properties, for: kCGImagePropertyHasAlpha),
                hasColorProfile: containsString(in: properties, for: kCGImagePropertyProfileName)
            )
        }
    }

    private static func orientation(
        in properties: CFDictionary
    ) throws -> NativeImageOrientation? {
        guard let value = integer(in: properties, for: kCGImagePropertyOrientation) else {
            return nil
        }
        guard let encodedValue = UInt8(exactly: value),
            let orientation = NativeImageOrientation(rawValue: encodedValue)
        else {
            throw NativeImageProbeError.invalidOrientation
        }
        return orientation
    }

    private static func integer(in properties: CFDictionary, for key: CFString) -> Int? {
        guard let pointer = valuePointer(in: properties, for: key) else {
            return nil
        }
        let value = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        let number = Unmanaged<CFNumber>.fromOpaque(pointer).takeUnretainedValue()

        var result: Int64 = 0
        guard CFNumberGetValue(number, .sInt64Type, &result) else {
            return nil
        }
        return Int(exactly: result)
    }

    private static func boolean(in properties: CFDictionary, for key: CFString) -> Bool? {
        guard let pointer = valuePointer(in: properties, for: key) else {
            return nil
        }
        let value = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        let boolean = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(boolean)
    }

    private static func containsString(in properties: CFDictionary, for key: CFString) -> Bool {
        guard let pointer = valuePointer(in: properties, for: key) else {
            return false
        }
        let value = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        return CFGetTypeID(value) == CFStringGetTypeID()
    }

    private static func valuePointer(
        in properties: CFDictionary,
        for key: CFString
    ) -> UnsafeRawPointer? {
        guard
            let pointer = CFDictionaryGetValue(
                properties,
                Unmanaged.passUnretained(key).toOpaque()
            )
        else {
            return nil
        }
        return pointer
    }
}
