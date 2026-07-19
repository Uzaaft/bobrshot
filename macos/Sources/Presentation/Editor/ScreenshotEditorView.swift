import AppKit
import SwiftUI

@MainActor
struct ScreenshotEditorView: View {
    typealias ExportAction = (Data) async throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var draft: ScreenshotDraft
    @State private var previewImage: NSImage?
    @State private var selectedTool: ScreenshotEditorTool = .arrow
    @State private var selectedColor = Color.red
    @State private var strokeWidth = 4.0
    @State private var gesture: EditorGesture?
    @State private var textEntry: EditorTextEntry?
    @State private var errorMessage: String?
    @State private var undoDepth: Int
    @State private var redoDepth = 0
    @State private var exportInProgress = false

    private let onCopy: ExportAction
    private let onSave: ExportAction
    private let onDone: () -> Void

    init(
        draft: ScreenshotDraft,
        onCopy: @escaping ExportAction,
        onSave: @escaping ExportAction,
        onDone: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        _previewImage = State(initialValue: NSImage(data: draft.sourcePNG))
        _undoDepth = State(initialValue: draft.editor.document.annotations.count)
        self.onCopy = onCopy
        self.onSave = onSave
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            Divider()
            editorCanvas
            Divider()
            actionBar
        }
        .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: handleEscape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot editor")
    }

    private var toolBar: some View {
        HStack(spacing: 10) {
            ControlGroup {
                ForEach(ScreenshotEditorTool.allCases) { tool in
                    toolButton(tool)
                }
            }
            .controlGroupStyle(.navigation)

            Divider()
                .frame(height: 22)

            ColorPicker("Color", selection: $selectedColor, supportsOpacity: true)
                .labelsHidden()
                .accessibilityLabel("Annotation color")
                .help("Annotation color")

            HStack(spacing: 6) {
                Image(systemName: "lineweight")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $strokeWidth, in: 1...24, step: 1)
                    .frame(width: 92)
                    .accessibilityLabel("Stroke width")
                    .accessibilityValue("\(Int(strokeWidth)) points")
                Text("\(Int(strokeWidth))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 4)

            ControlGroup {
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoDepth == 0)
                .accessibilityLabel("Undo annotation")
                .help("Undo (Command-Z)")

                Button(action: redo) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(redoDepth == 0)
                .accessibilityLabel("Redo annotation")
                .help("Redo (Shift-Command-Z)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolButton(_ tool: ScreenshotEditorTool) -> some View {
        Button {
            select(tool)
        } label: {
            Label(tool.title, systemImage: tool.systemImage)
                .labelStyle(.iconOnly)
                .symbolVariant(selectedTool == tool ? .fill : .none)
                .frame(minWidth: 20, minHeight: 20)
        }
        .buttonStyle(.bordered)
        .tint(selectedTool == tool ? .accentColor : nil)
        .keyboardShortcut(tool.shortcut, modifiers: [])
        .accessibilityLabel(tool.title)
        .accessibilityValue(selectedTool == tool ? "Selected" : "")
        .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
        .help("\(tool.title) (\(tool.shortcutDescription))")
    }

    private var editorCanvas: some View {
        GeometryReader { proxy in
            let viewport = proxy.frame(in: .local)
            let imageRect = fittedImageRect(in: viewport)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .accessibilityLabel("Screenshot preview")
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The screenshot could not be decoded.")
                    )
                }

                EditorInteractionCanvas(
                    imageSize: CGSize(width: draft.pixelWidth, height: draft.pixelHeight),
                    selectedTool: selectedTool,
                    color: selectedColor,
                    strokeWidth: strokeWidth,
                    gesture: $gesture,
                    textEntry: $textEntry,
                    onCommit: commit
                )
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)

                if let errorMessage {
                    errorBanner(errorMessage)
                        .padding(12)
                        .frame(maxWidth: 460)
                        .position(x: viewport.midX, y: viewport.maxY - 42)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .clipShape(Rectangle())
        }
        .padding(16)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("\(draft.pixelWidth) × \(draft.pixelHeight)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Screenshot size")
                .accessibilityValue("\(draft.pixelWidth) by \(draft.pixelHeight) pixels")

            if draft.hasEdits {
                Label("Edited", systemImage: "pencil.and.outline")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done", action: onDone)
                .keyboardShortcut(.cancelAction)

            Button {
                Task { await performExport(onCopy) }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(exportInProgress)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy edited screenshot (Shift-Command-C)")

            Button {
                Task { await performExport(onSave) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(exportInProgress)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save edited screenshot (Command-S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    colorSchemeContrast == .increased ? Color.primary : Color.secondary.opacity(0.3)
                )
        }
        .shadow(
            color: .black.opacity(colorSchemeContrast == .increased ? 0 : 0.16), radius: 8, y: 2
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private func fittedImageRect(in viewport: CGRect) -> CGRect {
        guard draft.pixelWidth > 0, draft.pixelHeight > 0 else { return .zero }
        let scale = min(
            viewport.width / CGFloat(draft.pixelWidth),
            viewport.height / CGFloat(draft.pixelHeight)
        )
        let size = CGSize(
            width: CGFloat(draft.pixelWidth) * scale,
            height: CGFloat(draft.pixelHeight) * scale
        )
        return CGRect(
            x: viewport.midX - size.width / 2,
            y: viewport.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func select(_ tool: ScreenshotEditorTool) {
        selectedTool = tool
        gesture = nil
        textEntry = nil
        errorMessage = nil
    }

    private func commit(_ annotation: ScreenshotAnnotation) {
        draft.apply(draft.editor.document.appending(annotation))
        undoDepth += 1
        redoDepth = 0
        renderPreview()
    }

    private func undo() {
        guard draft.undo() else { return }
        undoDepth = max(0, undoDepth - 1)
        redoDepth += 1
        renderPreview()
    }

    private func redo() {
        guard draft.redo() else { return }
        undoDepth += 1
        redoDepth = max(0, redoDepth - 1)
        renderPreview()
    }

    private func renderPreview() {
        do {
            previewImage = NSImage(data: try draft.renderedPNG())
            errorMessage = previewImage == nil ? "The edited screenshot could not be decoded." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performExport(_ action: ExportAction) async {
        guard !exportInProgress else { return }
        exportInProgress = true
        defer { exportInProgress = false }
        do {
            try await action(draft.renderedPNG())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleEscape() {
        if textEntry != nil || gesture != nil {
            textEntry = nil
            gesture = nil
        } else {
            onDone()
        }
    }
}

private struct EditorGesture: Equatable {
    let start: CGPoint
    var current: CGPoint
    var points: [CGPoint]
}

private struct EditorTextEntry: Equatable {
    let origin: CGPoint
    var value = ""
}

private struct EditorInteractionCanvas: View {
    let imageSize: CGSize
    let selectedTool: ScreenshotEditorTool
    let color: Color
    let strokeWidth: Double
    @Binding var gesture: EditorGesture?
    @Binding var textEntry: EditorTextEntry?
    let onCommit: (ScreenshotAnnotation) -> Void

    @FocusState private var textFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                currentGestureCanvas(size: proxy.size)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(viewSize: proxy.size))
                    .accessibilityLabel("Screenshot annotation canvas")
                    .accessibilityHint(
                        "Drag to add a \(selectedTool.title.lowercased()) annotation")

                if let textEntry {
                    textField(for: textEntry, viewSize: proxy.size)
                }
            }
        }
    }

    private func currentGestureCanvas(size: CGSize) -> some View {
        Canvas { context, _ in
            guard let gesture else { return }
            let scale = displayScale(for: size)
            let lineWidth = max(1, strokeWidth / scale)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let strokeColor = color

            switch selectedTool {
            case .line:
                context.stroke(
                    path(from: gesture.start, to: gesture.current), with: .color(strokeColor),
                    style: style)
            case .arrow:
                drawArrow(gesture, in: &context, color: strokeColor, style: style, scale: scale)
            case .rectangle:
                context.stroke(Path(gesture.rect), with: .color(strokeColor), style: style)
            case .ellipse:
                context.stroke(
                    Path(ellipseIn: gesture.rect), with: .color(strokeColor), style: style)
            case .freehand:
                context.stroke(
                    path(points: gesture.points), with: .color(strokeColor), style: style)
            case .blur:
                context.fill(Path(gesture.rect), with: .color(.secondary.opacity(0.22)))
                context.stroke(
                    Path(gesture.rect), with: .color(.secondary),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            case .pixelate:
                context.fill(Path(gesture.rect), with: .color(.secondary.opacity(0.3)))
                drawPixelGrid(gesture.rect, in: &context)
            case .redaction:
                context.fill(Path(gesture.rect), with: .color(.black.opacity(0.88)))
            case .text:
                break
            }
        }
    }

    private func dragGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard textEntry == nil else { return }
                let location = clamped(value.location, to: viewSize)
                if gesture == nil {
                    gesture = EditorGesture(start: location, current: location, points: [location])
                } else {
                    gesture?.current = location
                    if selectedTool == .freehand {
                        gesture?.points.append(location)
                    }
                }
            }
            .onEnded { value in
                guard textEntry == nil else { return }
                let location = clamped(value.location, to: viewSize)
                guard var completed = gesture else { return }
                completed.current = location
                gesture = nil

                if selectedTool == .text {
                    textEntry = EditorTextEntry(origin: location)
                    textFieldFocused = true
                    return
                }
                guard let annotation = annotation(from: completed, viewSize: viewSize) else {
                    return
                }
                onCommit(annotation)
            }
    }

    private func textField(for entry: EditorTextEntry, viewSize: CGSize) -> some View {
        TextField(
            "Annotation text",
            text: Binding(
                get: { textEntry?.value ?? "" },
                set: { textEntry?.value = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: min(260, max(120, viewSize.width - entry.origin.x - 8)))
        .offset(x: entry.origin.x, y: entry.origin.y)
        .focused($textFieldFocused)
        .onSubmit { commitText(viewSize: viewSize) }
        .onExitCommand { textEntry = nil }
        .accessibilityLabel("Annotation text")
        .task { textFieldFocused = true }
    }

    private func commitText(viewSize: CGSize) {
        guard let entry = textEntry else { return }
        textEntry = nil
        let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let origin = imagePoint(entry.origin, viewSize: viewSize)
        onCommit(
            ScreenshotAnnotation(
                kind: .text(
                    origin: origin,
                    value: value,
                    fontSize: max(12, strokeWidth * 5),
                    color: annotationColor
                ),
                stroke: annotationStroke
            )
        )
    }

    private func annotation(from gesture: EditorGesture, viewSize: CGSize) -> ScreenshotAnnotation?
    {
        let start = imagePoint(gesture.start, viewSize: viewSize)
        let end = imagePoint(gesture.current, viewSize: viewSize)
        let rect = AnnotationRect(
            x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
        let minimum = max(1, displayScale(for: viewSize))

        switch selectedTool {
        case .line where gesture.distance >= minimum:
            return ScreenshotAnnotation(
                kind: .line(start: start, end: end), stroke: annotationStroke)
        case .arrow where gesture.distance >= minimum:
            return ScreenshotAnnotation(
                kind: .arrow(start: start, end: end, headLength: max(10, strokeWidth * 4)),
                stroke: annotationStroke
            )
        case .rectangle where gesture.distance >= minimum:
            return ScreenshotAnnotation(kind: .rectangle(rect, fill: nil), stroke: annotationStroke)
        case .ellipse where gesture.distance >= minimum:
            return ScreenshotAnnotation(kind: .ellipse(rect, fill: nil), stroke: annotationStroke)
        case .freehand where gesture.points.count > 1:
            return ScreenshotAnnotation(
                kind: .freehand(gesture.points.map { imagePoint($0, viewSize: viewSize) }),
                stroke: annotationStroke
            )
        case .blur where gesture.distance >= minimum:
            return ScreenshotAnnotation(kind: .blur(rect, radius: 12), stroke: annotationStroke)
        case .pixelate where gesture.distance >= minimum:
            return ScreenshotAnnotation(kind: .pixelate(rect, scale: 14), stroke: annotationStroke)
        case .redaction where gesture.distance >= minimum:
            return ScreenshotAnnotation(
                kind: .redaction(rect, color: .black), stroke: annotationStroke)
        default:
            return nil
        }
    }

    private var annotationStroke: AnnotationStroke {
        AnnotationStroke(color: annotationColor, width: strokeWidth)
    }

    private var annotationColor: AnnotationColor {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .systemRed
        return AnnotationColor(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }

    private func imagePoint(_ point: CGPoint, viewSize: CGSize) -> AnnotationPoint {
        let scaleX = imageSize.width / max(1, viewSize.width)
        let scaleY = imageSize.height / max(1, viewSize.height)
        return AnnotationPoint(x: point.x * scaleX, y: point.y * scaleY)
    }

    private func displayScale(for viewSize: CGSize) -> Double {
        max(imageSize.width / max(1, viewSize.width), imageSize.height / max(1, viewSize.height))
    }

    private func clamped(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, point.x), size.width), y: min(max(0, point.y), size.height))
    }

    private func path(from start: CGPoint, to end: CGPoint) -> Path {
        var result = Path()
        result.move(to: start)
        result.addLine(to: end)
        return result
    }

    private func path(points: [CGPoint]) -> Path {
        var result = Path()
        guard let first = points.first else { return result }
        result.move(to: first)
        for point in points.dropFirst() { result.addLine(to: point) }
        return result
    }

    private func drawArrow(
        _ gesture: EditorGesture,
        in context: inout GraphicsContext,
        color: Color,
        style: StrokeStyle,
        scale: Double
    ) {
        context.stroke(
            path(from: gesture.start, to: gesture.current), with: .color(color), style: style)
        let angle = atan2(gesture.current.y - gesture.start.y, gesture.current.x - gesture.start.x)
        let length = max(10, strokeWidth * 4 / scale)
        let wing = Double.pi / 6
        let first = CGPoint(
            x: gesture.current.x - length * cos(angle - wing),
            y: gesture.current.y - length * sin(angle - wing)
        )
        let second = CGPoint(
            x: gesture.current.x - length * cos(angle + wing),
            y: gesture.current.y - length * sin(angle + wing)
        )
        var head = Path()
        head.move(to: first)
        head.addLine(to: gesture.current)
        head.addLine(to: second)
        context.stroke(head, with: .color(color), style: style)
    }

    private func drawPixelGrid(_ rect: CGRect, in context: inout GraphicsContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        var grid = Path()
        let spacing = 8.0
        for x in stride(from: rect.minX + spacing, to: rect.maxX, by: spacing) {
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for y in stride(from: rect.minY + spacing, to: rect.maxY, by: spacing) {
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.45)), lineWidth: 1)
    }
}

private extension EditorGesture {
    var rect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var distance: Double { hypot(current.x - start.x, current.y - start.y) }
}
