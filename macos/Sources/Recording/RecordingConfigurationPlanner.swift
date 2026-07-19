import Foundation

struct RecordingConfigurationPlan: Equatable, Sendable {
    let capture: CaptureConfigurationPlan
    let width: Int
    let height: Int
    let framesPerSecond: Int
    let videoBitRate: Int
}

enum RecordingConfigurationPlanner {
    static func plan(
        target: CaptureTarget,
        catalog: CaptureCatalog,
        options: ScreenRecordingOptions
    ) throws -> RecordingConfigurationPlan {
        guard (1...120).contains(options.framesPerSecond) else {
            throw ScreenRecordingError.invalidFrameRate(options.framesPerSecond)
        }
        if let bitRate = options.videoBitRate, bitRate <= 0 {
            throw ScreenRecordingError.invalidVideoBitRate(bitRate)
        }

        let capture = try CaptureConfigurationPlanner.plan(target: target, catalog: catalog)
        let width = encoderDimension(capture.outputWidth)
        let height = encoderDimension(capture.outputHeight)
        guard width >= 2, height >= 2 else {
            throw ScreenRecordingError.unsupportedDimensions(
                width: capture.outputWidth,
                height: capture.outputHeight
            )
        }

        return RecordingConfigurationPlan(
            capture: capture,
            width: width,
            height: height,
            framesPerSecond: options.framesPerSecond,
            videoBitRate: options.videoBitRate
                ?? recommendedBitRate(
                    width: width,
                    height: height,
                    framesPerSecond: options.framesPerSecond,
                    codec: options.codec
                )
        )
    }

    /// VideoToolbox's common H.264 and HEVC paths require even dimensions. Cropping at most one
    /// pixel avoids stretching the captured content or silently asking the encoder to rescale it.
    private static func encoderDimension(_ value: Int) -> Int {
        value - (value % 2)
    }

    private static func recommendedBitRate(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        codec: RecordingVideoCodec
    ) -> Int {
        let bitsPerPixel: Double = codec == .hevc ? 0.075 : 0.12
        let estimate = Double(width) * Double(height) * Double(framesPerSecond) * bitsPerPixel
        return min(max(Int(estimate.rounded()), 2_000_000), 80_000_000)
    }
}
