import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BobrshotAppModel

    var body: some View {
        Form {
            Section("Screen Recording") {
                LabeledContent("Access", value: model.permission.title)
                if model.permission.needsAction {
                    Button(model.permission == .denied ? "Open System Settings" : "Request Access")
                    {
                        model.managePermission()
                    }
                }
            }

            Section("Storage") {
                LabeledContent("Location") {
                    Text(model.storagePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.storagePath)
                }
                Button("Show in Finder") {
                    model.openStorageFolder()
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Capture Region", value: "⌃⇧⌘1")
                LabeledContent("Capture Window", value: "⌃⇧⌘2")
                LabeledContent("Capture Display", value: "⌃⇧⌘3")
                LabeledContent("Record Region", value: "⌃⇧⌘4")
            }

            Section("About") {
                LabeledContent("Bobrshot Core", value: BobrshotCore.version.description)
                    .monospacedDigit()
                Text("A fast, native capture tool for macOS power users.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 500)
    }
}
