import SwiftUI

@MainActor
struct BobrshotMenuBarView: View {
    let permission: MenuBarScreenCapturePermission
    let recordingStatus: MenuBarRecordingStatus
    let operationStatus: MenuBarOperationStatus
    let recentEntries: [CaptureHistoryEntry]
    let actions: MenuBarCaptureActions

    var body: some View {
        Group {
            captureCommands

            Divider()

            recordingCommand

            Divider()

            permissionCommand

            operationStatusView

            if !recentEntries.isEmpty {
                recentCapturesMenu
            }

            Button("Capture History…", systemImage: "clock.arrow.circlepath") {
                actions.openHistory()
            }

            Divider()

            Button("Settings…", systemImage: "gearshape") {
                actions.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit Bobrshot") {
                actions.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    @ViewBuilder
    private var captureCommands: some View {
        Button("Capture Region", systemImage: "viewfinder") {
            actions.captureRegion()
        }
        .keyboardShortcut("1", modifiers: [.command, .shift, .control])

        Button("Capture Window", systemImage: "macwindow") {
            actions.captureWindow()
        }
        .keyboardShortcut("2", modifiers: [.command, .shift, .control])

        Button("Capture Display", systemImage: "display") {
            actions.captureDisplay()
        }
        .keyboardShortcut("3", modifiers: [.command, .shift, .control])
    }

    @ViewBuilder
    private var recordingCommand: some View {
        switch recordingStatus {
        case .idle:
            Menu("Start Screen Recording", systemImage: "record.circle") {
                Button("Record Region") {
                    actions.startRegionRecording()
                }
                .keyboardShortcut("4", modifiers: [.command, .shift, .control])
                Button("Record Window") {
                    actions.startWindowRecording()
                }
                Button("Record Display") {
                    actions.startDisplayRecording()
                }
            }
        case .starting:
            Label("Starting Screen Recording…", systemImage: "record.circle")
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isStaticText)
        case .recording:
            Button("Stop Screen Recording", systemImage: "stop.circle.fill") {
                actions.stopScreenRecording()
            }
        case .stopping:
            Label("Finishing Screen Recording…", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isStaticText)
        case let .failed(message):
            Label("Screen Recording Failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .help(message)
                .accessibilityLabel("Screen recording failed: \(message)")
                .accessibilityAddTraits(.isStaticText)

            Button("Try Screen Recording Again", systemImage: "arrow.clockwise") {
                actions.startRegionRecording()
            }
        }
    }

    @ViewBuilder
    private var operationStatusView: some View {
        switch operationStatus {
        case .idle:
            EmptyView()
        case let .working(message):
            Label(message, systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isStaticText)
        case let .failed(message):
            Label("Capture Failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .help(message)
                .accessibilityLabel("Capture failed: \(message)")
                .accessibilityAddTraits(.isStaticText)
        }
    }

    @ViewBuilder
    private var permissionCommand: some View {
        if permission.needsAction {
            Button(permission.title, systemImage: permission.systemImage) {
                actions.manageScreenCapturePermission()
            }
        } else {
            Label(permission.title, systemImage: permission.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var recentCapturesMenu: some View {
        Menu("Recent Captures", systemImage: "clock") {
            ForEach(recentEntries.prefix(5)) { entry in
                Button {
                    actions.openHistoryEntry(entry)
                } label: {
                    Label(
                        entry.fileURL.lastPathComponent, systemImage: entry.presentationSystemImage)
                }
                .accessibilityLabel("Open \(entry.presentationTitle)")
                .accessibilityHint(entry.accessibilityDescription)
            }
        }
    }
}
