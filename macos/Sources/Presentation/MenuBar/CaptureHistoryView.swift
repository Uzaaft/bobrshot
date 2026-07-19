import SwiftUI

@MainActor
struct CaptureHistoryView: View {
    let state: CaptureHistoryPresentationState
    let actions: CaptureHistoryActions

    @State private var selection: UUID?

    var body: some View {
        content
            .navigationTitle("Capture History")
            .frame(minWidth: 620, minHeight: 400)
            .toolbar { historyToolbar }
            .onChange(of: entryIDs) { _, currentIDs in
                if let selection, !currentIDs.contains(selection) {
                    self.selection = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ContentUnavailableView {
                Label("Loading Capture History", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Reading saved screenshots and recordings.")
            }
            .accessibilityElement(children: .combine)

        case let .failed(message):
            ContentUnavailableView {
                Label("Capture History Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    actions.retry()
                }
            }
            .accessibilityElement(children: .contain)

        case let .loaded(entries) where entries.isEmpty:
            ContentUnavailableView {
                Label("No Captures Yet", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Screenshots and recordings you save will appear here.")
            }
            .accessibilityElement(children: .combine)

        case let .loaded(entries):
            historyList(entries)
        }
    }

    private func historyList(_ entries: [CaptureHistoryEntry]) -> some View {
        List(entries, selection: $selection) { entry in
            CaptureHistoryRow(entry: entry)
                .tag(entry.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    actions.open(entry)
                }
                .contextMenu {
                    historyActions(for: entry)
                }
        }
        .listStyle(.inset)
        .accessibilityLabel("Saved captures")
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Open", systemImage: "arrow.up.forward.app") {
                withSelectedEntry(actions.open)
            }
            .disabled(selectedEntry == nil)
            .keyboardShortcut(.return, modifiers: [])
            .help("Open the selected capture")

            Button("Copy", systemImage: "doc.on.doc") {
                withSelectedEntry(actions.copy)
            }
            .disabled(selectedEntry == nil)
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy the selected capture")

            Button("Reveal in Finder", systemImage: "folder") {
                withSelectedEntry(actions.revealInFinder)
            }
            .disabled(selectedEntry == nil)
            .help("Reveal the selected capture in Finder")

            Button("Delete", systemImage: "trash", role: .destructive) {
                withSelectedEntry { entry in
                    actions.delete(entry)
                    selection = nil
                }
            }
            .disabled(selectedEntry == nil)
            .keyboardShortcut(.delete, modifiers: [])
            .help("Delete the selected capture")
        }
    }

    @ViewBuilder
    private func historyActions(for entry: CaptureHistoryEntry) -> some View {
        Button("Open") {
            actions.open(entry)
        }

        Button("Copy") {
            actions.copy(entry)
        }

        Button("Reveal in Finder") {
            actions.revealInFinder(entry)
        }

        Divider()

        Button("Delete", role: .destructive) {
            actions.delete(entry)
            if selection == entry.id {
                selection = nil
            }
        }
    }

    private var entries: [CaptureHistoryEntry] {
        guard case let .loaded(entries) = state else { return [] }
        return entries
    }

    private var entryIDs: [UUID] {
        entries.map(\.id)
    }

    private var selectedEntry: CaptureHistoryEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    private func withSelectedEntry(_ action: (CaptureHistoryEntry) -> Void) {
        guard let selectedEntry else { return }
        action(selectedEntry)
    }
}

private struct CaptureHistoryRow: View {
    let entry: CaptureHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.presentationSystemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.presentationTitle)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(entry.presentationKind)
                    if let dimensions = entry.presentationDimensions {
                        Text(dimensions)
                    }
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(entry.byteCount),
                            countStyle: .file
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.presentationTitle)
        .accessibilityValue(
            "\(entry.accessibilityDescription), created \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"
        )
        .accessibilityHint("Double-click to open")
    }
}
