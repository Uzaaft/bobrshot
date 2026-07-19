import Foundation

struct AnnotationPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
}

struct AnnotationRect: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var standardized: AnnotationRect {
        AnnotationRect(
            x: width < 0 ? x + width : x,
            y: height < 0 ? y + height : y,
            width: abs(width),
            height: abs(height)
        )
    }
}

struct AnnotationColor: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let black = AnnotationColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let red = AnnotationColor(red: 1, green: 0, blue: 0, alpha: 1)
}

struct AnnotationStroke: Codable, Hashable, Sendable {
    let color: AnnotationColor
    let width: Double

    init(color: AnnotationColor = .red, width: Double = 3) {
        self.color = color
        self.width = width
    }
}

enum AnnotationKind: Codable, Hashable, Sendable {
    case line(start: AnnotationPoint, end: AnnotationPoint)
    case arrow(start: AnnotationPoint, end: AnnotationPoint, headLength: Double)
    case rectangle(AnnotationRect, fill: AnnotationColor?)
    case ellipse(AnnotationRect, fill: AnnotationColor?)
    case freehand([AnnotationPoint])
    case text(origin: AnnotationPoint, value: String, fontSize: Double, color: AnnotationColor)
    case blur(AnnotationRect, radius: Double)
    case pixelate(AnnotationRect, scale: Double)
    case redaction(AnnotationRect, color: AnnotationColor)
}

struct ScreenshotAnnotation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: AnnotationKind
    let stroke: AnnotationStroke

    init(id: UUID = UUID(), kind: AnnotationKind, stroke: AnnotationStroke = AnnotationStroke()) {
        self.id = id
        self.kind = kind
        self.stroke = stroke
    }
}

struct AnnotationDocument: Codable, Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let annotations: [ScreenshotAnnotation]

    init(pixelWidth: Int, pixelHeight: Int, annotations: [ScreenshotAnnotation] = []) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.annotations = annotations
    }

    func appending(_ annotation: ScreenshotAnnotation) -> AnnotationDocument {
        AnnotationDocument(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            annotations: annotations + [annotation]
        )
    }

    func removing(id: UUID) -> AnnotationDocument {
        AnnotationDocument(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            annotations: annotations.filter { $0.id != id }
        )
    }
}

struct AnnotationEditorState: Equatable, Sendable {
    private(set) var document: AnnotationDocument
    private(set) var undoStack: [AnnotationDocument] = []
    private(set) var redoStack: [AnnotationDocument] = []

    init(document: AnnotationDocument) {
        self.document = document
    }

    mutating func apply(_ next: AnnotationDocument) {
        guard next != document else { return }
        undoStack.append(document)
        document = next
        redoStack.removeAll(keepingCapacity: true)
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(document)
        document = previous
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(document)
        document = next
        return true
    }
}
