import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AnnotationRenderError: Error, Equatable, LocalizedError, Sendable {
    case invalidDocument
    case invalidSourceImage
    case contextCreationFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidDocument: "The annotation canvas dimensions are invalid."
        case .invalidSourceImage: "The screenshot data could not be decoded."
        case .contextCreationFailed: "The annotation canvas could not be created."
        case .encodingFailed: "The annotated screenshot could not be encoded."
        }
    }
}

enum AnnotationRenderer {
    static func renderPNG(sourceData: Data, document: AnnotationDocument) throws -> Data {
        guard document.pixelWidth > 0, document.pixelHeight > 0 else {
            throw AnnotationRenderError.invalidDocument
        }
        guard
            let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw AnnotationRenderError.invalidSourceImage }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: document.pixelWidth,
                height: document.pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw AnnotationRenderError.contextCreationFailed }

        let canvas = CGRect(x: 0, y: 0, width: document.pixelWidth, height: document.pixelHeight)
        context.interpolationQuality = .high
        context.draw(image, in: canvas)
        context.translateBy(x: 0, y: CGFloat(document.pixelHeight))
        context.scaleBy(x: 1, y: -1)

        for annotation in document.annotations {
            draw(annotation, source: image, in: context)
        }

        guard let output = context.makeImage() else {
            throw AnnotationRenderError.contextCreationFailed
        }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { throw AnnotationRenderError.encodingFailed }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AnnotationRenderError.encodingFailed
        }
        return data as Data
    }

    private static func draw(
        _ annotation: ScreenshotAnnotation,
        source: CGImage,
        in context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(annotation.stroke.color.cgColor)
        context.setLineWidth(max(0.5, annotation.stroke.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case let .line(start, end):
            stroke(points: [start, end], in: context)
        case let .arrow(start, end, headLength):
            stroke(points: [start, end], in: context)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = max(1, headLength)
            let wing = Double.pi / 6
            stroke(
                points: [
                    AnnotationPoint(
                        x: end.x - length * cos(angle - wing), y: end.y - length * sin(angle - wing)
                    ),
                    end,
                    AnnotationPoint(
                        x: end.x - length * cos(angle + wing), y: end.y - length * sin(angle + wing)
                    ),
                ],
                in: context
            )
        case let .rectangle(rect, fill):
            drawShape(rect.standardized.cgRect, ellipse: false, fill: fill, in: context)
        case let .ellipse(rect, fill):
            drawShape(rect.standardized.cgRect, ellipse: true, fill: fill, in: context)
        case let .freehand(points):
            stroke(points: points, in: context)
        case let .text(origin, value, fontSize, color):
            drawText(value, at: origin, fontSize: fontSize, color: color, in: context)
        case let .blur(rect, radius):
            drawEffect(
                "CIGaussianBlur", amount: max(0, radius), rect: rect, source: source, in: context)
        case let .pixelate(rect, scale):
            drawEffect(
                "CIPixellate", amount: max(1, scale), rect: rect, source: source, in: context)
        case let .redaction(rect, color):
            context.setFillColor(color.cgColor)
            context.fill(rect.standardized.cgRect)
        }
    }

    private static func stroke(points: [AnnotationPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first.cgPoint)
        for point in points.dropFirst() { context.addLine(to: point.cgPoint) }
        context.strokePath()
    }

    private static func drawShape(
        _ rect: CGRect,
        ellipse: Bool,
        fill: AnnotationColor?,
        in context: CGContext
    ) {
        if let fill {
            context.setFillColor(fill.cgColor)
            ellipse ? context.fillEllipse(in: rect) : context.fill(rect)
        }
        ellipse ? context.strokeEllipse(in: rect) : context.stroke(rect)
    }

    private static func drawText(
        _ value: String,
        at origin: AnnotationPoint,
        fontSize: Double,
        color: AnnotationColor,
        in context: CGContext
    ) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName(
                "Helvetica" as CFString, max(1, fontSize), nil),
            kCTForegroundColorAttributeName: color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, value as CFString, attributes as CFDictionary)
        )
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + max(1, fontSize))
        CTLineDraw(line, context)
    }

    private static func drawEffect(
        _ filterName: String,
        amount: Double,
        rect: AnnotationRect,
        source: CGImage,
        in context: CGContext
    ) {
        let target = rect.standardized.cgRect
        guard !target.isEmpty else { return }
        let input = CIImage(cgImage: source)
        let parameters: [String: Any] =
            filterName == "CIPixellate"
            ? [kCIInputImageKey: input, kCIInputScaleKey: amount]
            : [kCIInputImageKey: input, kCIInputRadiusKey: amount]
        guard
            let filtered = CIFilter(name: filterName, parameters: parameters)?.outputImage,
            let output = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(
                filtered,
                from: input.extent
            )
        else { return }
        context.clip(to: target)
        context.draw(output, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    }
}

private extension AnnotationPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension AnnotationRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

private extension AnnotationColor {
    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            components: [red, green, blue, alpha]
        ) ?? CGColor(gray: 0, alpha: 1)
    }
}
