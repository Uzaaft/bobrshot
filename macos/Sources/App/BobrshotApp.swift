import AppKit
import SwiftUI

@main
@MainActor
struct BobrshotApp: App {
    @NSApplicationDelegateAdaptor(BobrshotAppDelegate.self) private var appDelegate
    @StateObject private var model = BobrshotAppModel()

    var body: some Scene {
        MenuBarExtra {
            BobrshotMenuScene(model: model)
        } label: {
            BobrshotStatusLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Capture History", id: "history") {
            CaptureHistoryScene(model: model)
        }
        .defaultSize(width: 720, height: 480)

        Window("Bobrshot Settings", id: "settings") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)

        WindowGroup("Screenshot Editor", id: "editor", for: UUID.self) { $draftID in
            ScreenshotEditorScene(model: model, draftID: draftID)
        }
        .defaultSize(width: 960, height: 700)
    }
}

private struct BobrshotMenuScene: View {
    @ObservedObject var model: BobrshotAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        BobrshotMenuBarView(
            permission: model.permission,
            recordingStatus: model.recordingStatus,
            operationStatus: model.operationStatus,
            recentEntries: model.recentEntries,
            actions: MenuBarCaptureActions(
                captureRegion: { model.capture(mode: .region) },
                captureWindow: { model.capture(mode: .window) },
                captureDisplay: { model.capture(mode: .display) },
                startRegionRecording: { model.startRecording(mode: .region) },
                startWindowRecording: { model.startRecording(mode: .window) },
                startDisplayRecording: { model.startRecording(mode: .display) },
                stopScreenRecording: model.stopRecording,
                manageScreenCapturePermission: model.managePermission,
                openHistory: { openWindow(id: "history") },
                openHistoryEntry: model.open,
                openSettings: { openWindow(id: "settings") },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )
        .onAppear {
            model.refreshPermission()
            Task { await model.refreshHistory() }
        }
    }

}

private struct BobrshotStatusLabel: View {
    @ObservedObject var model: BobrshotAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(
            model.isRecording ? "Bobrshot is recording" : "Bobrshot",
            systemImage: model.isRecording ? "record.circle.fill" : "viewfinder"
        )
        .onChange(of: model.pendingEditorID) { _, id in
            guard let id else { return }
            openWindow(id: "editor", value: id)
            model.consumePendingEditor(id: id)
        }
    }
}

private struct CaptureHistoryScene: View {
    @ObservedObject var model: BobrshotAppModel

    var body: some View {
        CaptureHistoryView(
            state: model.historyState,
            actions: CaptureHistoryActions(
                open: model.open,
                revealInFinder: model.revealInFinder,
                copy: model.copy,
                delete: model.delete,
                retry: { Task { await model.refreshHistory() } }
            )
        )
        .task { await model.refreshHistory() }
    }
}

private struct ScreenshotEditorScene: View {
    @ObservedObject var model: BobrshotAppModel
    let draftID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let draftID, let draft = model.draft(id: draftID) {
                ScreenshotEditorView(
                    draft: draft,
                    onCopy: model.copyRenderedPNG,
                    onSave: model.saveRenderedPNG,
                    onDone: { dismiss() }
                )
            } else {
                ContentUnavailableView(
                    "Screenshot Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("This screenshot draft is no longer available.")
                )
            }
        }
        .onDisappear {
            if let draftID { model.discardDraft(id: draftID) }
        }
    }
}
