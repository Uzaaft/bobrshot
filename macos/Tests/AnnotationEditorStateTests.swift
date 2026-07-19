import Foundation
import XCTest

final class AnnotationEditorStateTests: XCTestCase {
    private static let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    func testUndoAndRedoRestoreWholeDocuments() {
        let original = AnnotationDocument(pixelWidth: 100, pixelHeight: 80)
        let mark = ScreenshotAnnotation(
            kind: .line(
                start: AnnotationPoint(x: 1, y: 2),
                end: AnnotationPoint(x: 30, y: 40)
            )
        )
        var editor = AnnotationEditorState(document: original)

        editor.apply(original.appending(mark))
        XCTAssertEqual(editor.document.annotations, [mark])
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.document, original)
        XCTAssertTrue(editor.redo())
        XCTAssertEqual(editor.document.annotations, [mark])
    }

    func testNewEditClearsRedoHistory() {
        let original = AnnotationDocument(pixelWidth: 100, pixelHeight: 80)
        let first = ScreenshotAnnotation(
            kind: .redaction(AnnotationRect(x: 0, y: 0, width: 10, height: 10), color: .black))
        let second = ScreenshotAnnotation(
            kind: .ellipse(AnnotationRect(x: 5, y: 5, width: 10, height: 10), fill: nil))
        var editor = AnnotationEditorState(document: original)

        editor.apply(original.appending(first))
        XCTAssertTrue(editor.undo())
        editor.apply(original.appending(second))

        XCTAssertFalse(editor.redo())
        XCTAssertEqual(editor.document.annotations, [second])
    }

    func testRendererProducesDecodablePNGAtDocumentDimensions() throws {
        let document = AnnotationDocument(
            pixelWidth: 1,
            pixelHeight: 1,
            annotations: [
                ScreenshotAnnotation(
                    kind: .redaction(
                        AnnotationRect(x: 0, y: 0, width: 1, height: 1),
                        color: .black
                    )
                )
            ]
        )

        let rendered = try AnnotationRenderer.renderPNG(sourceData: Self.png, document: document)
        let descriptor = try NativeImageProbe.inspect(rendered)

        XCTAssertEqual(descriptor.format, .png)
        XCTAssertEqual(descriptor.widthPixels, 1)
        XCTAssertEqual(descriptor.heightPixels, 1)
    }

    func testRendererRejectsInvalidInputs() {
        XCTAssertThrowsError(
            try AnnotationRenderer.renderPNG(
                sourceData: Self.png,
                document: AnnotationDocument(pixelWidth: 0, pixelHeight: 1)
            )
        ) { error in
            XCTAssertEqual(error as? AnnotationRenderError, .invalidDocument)
        }

        XCTAssertThrowsError(
            try AnnotationRenderer.renderPNG(
                sourceData: Data([0, 1]),
                document: AnnotationDocument(pixelWidth: 1, pixelHeight: 1)
            )
        ) { error in
            XCTAssertEqual(error as? AnnotationRenderError, .invalidSourceImage)
        }
    }
}
