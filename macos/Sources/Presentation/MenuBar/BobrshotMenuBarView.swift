import SwiftUI

@MainActor
struct BobrshotMenuBarView: View {
    let permission: MenuBarScreenCapturePermission
    let recordingStatus: MenuBarRecordingStatus
    let recentEntries: [CaptureHistoryEntry]
    let actions: MenuBarCaptureActions

    var body: some View {
        Group {
            captureCommands

            Divider()

            recordingCommand

            Divider()

            permissionCommand

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

        Button("Capture Window", systemImage: "macwindow") {
            actions.captureWindow()
        }

        Button("Capture Display", systemImage: "display") {
            actions.captureDisplay()
        }
    }

    @ViewBuilder
    private var recordingCommand: some View {
        switch recordingStatus {
        case .idle:
            Button("Start Screen Recording", systemImage: "record.circle") {
                actions.startScreenRecording()
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
                actions.startScreenRecording()
            }
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
