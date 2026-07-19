import SwiftUI

enum ScreenshotEditorTool: String, CaseIterable, Identifiable, Sendable {
    case line
    case arrow
    case rectangle
    case ellipse
    case freehand
    case text
    case blur
    case pixelate
    case redaction

    var id: Self { self }

    var title: String {
        switch self {
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .freehand: "Draw"
        case .text: "Text"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .redaction: "Redact"
        }
    }

    var systemImage: String {
        switch self {
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .freehand: "pencil.tip"
        case .text: "textformat"
        case .blur: "drop.halffull"
        case .pixelate: "square.grid.3x3.square"
        case .redaction: "rectangle.fill"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .line: "l"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .freehand: "p"
        case .text: "t"
        case .blur: "b"
        case .pixelate: "x"
        case .redaction: "d"
        }
    }

    var shortcutDescription: String {
        String(shortcut.character).uppercased()
    }
}
