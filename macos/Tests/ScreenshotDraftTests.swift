import Foundation
import XCTest

final class ScreenshotDraftTests: XCTestCase {
    private static let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    func testUneditedDraftPreservesOriginalBytes() throws {
        let draft = makeDraft()

        XCTAssertFalse(draft.hasEdits)
        XCTAssertEqual(try draft.renderedPNG(), Self.png)
    }

    func testEditedDraftRendersAndSupportsUndo() throws {
        var draft = makeDraft()
        let redaction = ScreenshotAnnotation(
            kind: .redaction(
                AnnotationRect(x: 0, y: 0, width: 1, height: 1),
                color: .black
            )
        )

        draft.apply(draft.editor.document.appending(redaction))
        XCTAssertTrue(draft.hasEdits)
        XCTAssertNoThrow(try NativeImageProbe.inspect(draft.renderedPNG()))
        XCTAssertTrue(draft.undo())
        XCTAssertEqual(try draft.renderedPNG(), Self.png)
        XCTAssertTrue(draft.redo())
        XCTAssertTrue(draft.hasEdits)
    }

    private func makeDraft() -> ScreenshotDraft {
        ScreenshotDraft(
            capturedAt: Date(timeIntervalSince1970: 0),
            sourcePNG: Self.png,
            editor: AnnotationEditorState(
                document: AnnotationDocument(pixelWidth: 1, pixelHeight: 1)
            )
        )
    }
}
