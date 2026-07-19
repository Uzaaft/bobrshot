import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BobrshotAppDelegate: NSObject, NSApplicationDelegate {
    private var visualCheckWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            guard
                let argument = ProcessInfo.processInfo.arguments.first(where: {
                    $0.hasPrefix("--visual-check=")
                })
            else { return }
            let surface = String(argument.dropFirst("--visual-check=".count))
            showVisualCheckWindow(surface: surface)
        #endif
    }

    #if DEBUG
        private func showVisualCheckWindow(surface: String) {
            let content: AnyView
            let title: String
            switch surface {
            case "history":
                title = "Capture History"
                content = AnyView(
                    CaptureHistoryView(
                        state: .loaded(Self.sampleHistory),
                        actions: CaptureHistoryActions(
                            open: { _ in },
                            revealInFinder: { _ in },
                            copy: { _ in },
                            delete: { _ in },
                            retry: {}
                        )
                    )
                )
            case "editor":
                title = "Screenshot Editor"
                content = AnyView(
                    ScreenshotEditorView(
                        draft: Self.sampleDraft,
                        onCopy: { _ in },
                        onSave: { _ in }
                    )
                )
            default:
                let model = BobrshotAppModel()
                title = "Bobrshot Settings"
                content = AnyView(ContentView(model: model))
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.contentViewController = NSHostingController(rootView: content)
            window.center()
            window.makeKeyAndOrderFront(nil)
            visualCheckWindow = window
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
                guard let view = window?.contentView,
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
                let output = URL(fileURLWithPath: "/tmp/bobrshot-\(surface).png")
                try? png.write(to: output, options: .atomic)
            }
        }

        private static var sampleHistory: [CaptureHistoryEntry] {
            [
                CaptureHistoryEntry(
                    createdAt: Date(),
                    fileURL: URL(fileURLWithPath: "/tmp/Bobrshot Region.png"),
                    kind: .screenshot(.png),
                    byteCount: 1_284_320,
                    pixelWidth: 2560,
                    pixelHeight: 1440
                ),
                CaptureHistoryEntry(
                    createdAt: Date().addingTimeInterval(-3_600),
                    fileURL: URL(fileURLWithPath: "/tmp/Bobrshot Recording.mov"),
                    kind: .screenRecording(.h264),
                    byteCount: 18_740_224
                ),
                CaptureHistoryEntry(
                    createdAt: Date().addingTimeInterval(-86_400),
                    fileURL: URL(fileURLWithPath: "/tmp/Bobrshot Window.png"),
                    kind: .screenshot(.png),
                    byteCount: 482_120,
                    pixelWidth: 1320,
                    pixelHeight: 860
                ),
            ]
        }

        private static var sampleDraft: ScreenshotDraft {
            let data = samplePNG(width: 1440, height: 900)
            return ScreenshotDraft(
                sourcePNG: data,
                editor: AnnotationEditorState(
                    document: AnnotationDocument(pixelWidth: 1440, pixelHeight: 900)
                )
            )
        }

        private static func samplePNG(width: Int, height: Int) -> Data {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard
                let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return Data() }

            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor)
            context.fill(CGRect(x: 80, y: 80, width: width - 160, height: height - 160))
            context.setFillColor(NSColor.controlAccentColor.cgColor)
            context.fill(CGRect(x: 160, y: 180, width: 420, height: 54))
            context.setFillColor(NSColor.secondaryLabelColor.cgColor)
            context.fill(CGRect(x: 160, y: 270, width: 820, height: 22))
            context.fill(CGRect(x: 160, y: 312, width: 620, height: 22))

            guard let image = context.makeImage() else { return Data() }
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data,
                    UTType.png.identifier as CFString,
                    1,
                    nil
                )
            else { return Data() }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return Data() }
            return data as Data
        }
    #endif
}
