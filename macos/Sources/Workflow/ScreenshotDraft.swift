import Foundation

struct ScreenshotDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let sourcePNG: Data
    private(set) var editor: AnnotationEditorState

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        sourcePNG: Data,
        editor: AnnotationEditorState
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.sourcePNG = sourcePNG
        self.editor = editor
    }

    var pixelWidth: Int { editor.document.pixelWidth }
    var pixelHeight: Int { editor.document.pixelHeight }
    var hasEdits: Bool { !editor.document.annotations.isEmpty }

    mutating func apply(_ document: AnnotationDocument) {
        editor.apply(document)
    }

    @discardableResult
    mutating func undo() -> Bool {
        editor.undo()
    }

    @discardableResult
    mutating func redo() -> Bool {
        editor.redo()
    }

    func renderedPNG() throws -> Data {
        guard hasEdits else { return sourcePNG }
        return try AnnotationRenderer.renderPNG(sourceData: sourcePNG, document: editor.document)
    }
}
