import AppKit
import Combine
import Foundation

@MainActor
final class BobrshotAppModel: ObservableObject {
    @Published private(set) var permission: MenuBarScreenCapturePermission = .checking
    @Published private(set) var recordingStatus: MenuBarRecordingStatus = .idle
    @Published private(set) var operationStatus: MenuBarOperationStatus = .idle
    @Published private(set) var historyState: CaptureHistoryPresentationState = .loading
    @Published private(set) var recentEntries: [CaptureHistoryEntry] = []
    @Published private(set) var pendingEditorID: UUID?

    private(set) var services: BobrshotServiceContainer?
    private var drafts: [UUID: ScreenshotDraft] = [:]

    private let selectionController = CaptureSelectionOverlayController()
    private var requestedPermissionThisLaunch = false
    private lazy var globalHotKeys = GlobalHotKeyController(
        actions: GlobalHotKeyActions(
            captureRegion: { [weak self] in self?.capture(mode: .region) },
            captureWindow: { [weak self] in self?.capture(mode: .window) },
            captureDisplay: { [weak self] in self?.capture(mode: .display) },
            recordRegion: { [weak self] in self?.startRecording(mode: .region) }
        )
    )

    init() {
        do {
            let services = try BobrshotServiceContainer()
            self.services = services
            updatePermission(using: services.screenshots.permission)
            Task { await refreshHistory() }
        } catch {
            operationStatus = .failed(error.localizedDescription)
            historyState = .failed(error.localizedDescription)
        }
        startGlobalHotKeys()
    }

    var storagePath: String {
        services?.paths.root.path(percentEncoded: false) ?? "Unavailable"
    }

    var isRecording: Bool {
        switch recordingStatus {
        case .starting, .recording, .stopping:
            true
        case .idle, .failed:
            false
        }
    }

    func refreshPermission() {
        guard let services else { return }
        updatePermission(using: services.screenshots.permission)
    }

    func managePermission() {
        guard let services else { return }
        refreshPermission()
        if permission == .authorized { return }
        if requestedPermissionThisLaunch {
            openScreenRecordingSettings()
            return
        }
        requestPermission(using: services)
    }

    func capture(mode: CaptureSelectionMode) {
        guard let services, beginCaptureOperation("Choose a capture target") else { return }

        Task {
            do {
                guard ensureAuthorized() else { return }
                let catalog = try await services.screenshots.catalog()
                let outcome = await selectionController.select(mode: mode, catalog: catalog)
                guard case let .selected(target) = outcome else {
                    operationStatus = .idle
                    return
                }

                operationStatus = .working("Capturing screenshot")
                let draft = try await services.screenshots.capture(target: target)
                drafts[draft.id] = draft
                operationStatus = .idle
                pendingEditorID = draft.id
            } catch {
                operationStatus = .failed(error.localizedDescription)
            }
        }
    }

    func startRecording(mode: CaptureSelectionMode) {
        guard let services else { return }
        switch recordingStatus {
        case .idle, .failed:
            break
        case .starting, .recording, .stopping:
            return
        }
        recordingStatus = .starting

        Task {
            do {
                guard ensureAuthorized() else {
                    recordingStatus = .idle
                    return
                }
                let catalog = try await services.screenshots.catalog()
                let outcome = await selectionController.select(mode: mode, catalog: catalog)
                guard case let .selected(target) = outcome else {
                    recordingStatus = .idle
                    return
                }
                _ = try await services.recordings.start(
                    target: target,
                    in: services.paths.recordings
                )
                recordingStatus = .recording
                operationStatus = .idle
            } catch {
                recordingStatus = .failed(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        guard let services, recordingStatus == .recording else { return }
        recordingStatus = .stopping
        Task {
            do {
                _ = try await services.recordings.stop()
                recordingStatus = .idle
                await refreshHistory()
            } catch {
                recordingStatus = .failed(error.localizedDescription)
            }
        }
    }

    func draft(id: UUID) -> ScreenshotDraft? {
        drafts[id]
    }

    func discardDraft(id: UUID) {
        drafts[id] = nil
    }

    func consumePendingEditor(id: UUID) {
        guard pendingEditorID == id else { return }
        pendingEditorID = nil
    }

    func startGlobalHotKeys() {
        globalHotKeys.register()
    }

    func copyRenderedPNG(_ data: Data) throws {
        try ScreenshotClipboard.copyImage(data: data)
    }

    func saveRenderedPNG(_ data: Data) async throws {
        guard let services else { throw BobrshotApplicationError.servicesUnavailable }
        _ = try await services.screenshots.exportRenderedPNG(
            data,
            to: services.paths.screenshots
        )
        await refreshHistory()
    }

    func refreshHistory() async {
        guard let services else { return }
        historyState = .loading
        do {
            let entries = try await services.historyStore.entries()
            recentEntries = entries
            historyState = .loaded(entries)
        } catch {
            historyState = .failed(error.localizedDescription)
        }
    }

    func open(_ entry: CaptureHistoryEntry) {
        guard NSWorkspace.shared.open(entry.fileURL) else {
            operationStatus = .failed("The selected capture could not be opened.")
            return
        }
        operationStatus = .idle
    }

    func revealInFinder(_ entry: CaptureHistoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
    }

    func copy(_ entry: CaptureHistoryEntry) {
        guard let services else { return }
        Task {
            do {
                switch entry.kind {
                case .screenshot:
                    let data = try await services.historyStore.data(for: entry)
                    try ScreenshotClipboard.copyImage(data: data)
                case .screenRecording:
                    try ScreenshotClipboard.copyFile(at: entry.fileURL)
                }
                operationStatus = .idle
            } catch {
                operationStatus = .failed(error.localizedDescription)
            }
        }
    }

    func delete(_ entry: CaptureHistoryEntry) {
        guard let services else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Capture?"
        alert.informativeText = "This permanently deletes \(entry.fileURL.lastPathComponent)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await services.historyStore.remove(id: entry.id, deleteFile: true)
                await refreshHistory()
            } catch {
                operationStatus = .failed(error.localizedDescription)
            }
        }
    }

    func openStorageFolder() {
        guard let services else { return }
        NSWorkspace.shared.open(services.paths.root)
    }

    private func beginCaptureOperation(_ message: String) -> Bool {
        switch operationStatus {
        case .idle, .failed:
            break
        case .working:
            return false
        }
        guard recordingStatus == .idle else { return false }
        operationStatus = .working(message)
        return true
    }

    private func ensureAuthorized() -> Bool {
        refreshPermission()
        if permission == .authorized { return true }
        guard let services else { return false }
        if !requestedPermissionThisLaunch {
            return requestPermission(using: services)
        }
        presentPermissionDeniedAlert()
        return false
    }

    private func updatePermission(using status: ScreenCapturePermission) {
        switch status {
        case .granted:
            permission = .authorized
            if case .failed = operationStatus {
                operationStatus = .idle
            }
        case .denied:
            permission = requestedPermissionThisLaunch ? .denied : .notDetermined
        }
    }

    @discardableResult
    private func requestPermission(using services: BobrshotServiceContainer) -> Bool {
        requestedPermissionThisLaunch = true
        NSApp.activate(ignoringOtherApps: true)
        updatePermission(using: services.screenshots.requestPermission())
        guard permission == .authorized else {
            operationStatus = .failed(
                "Screen Recording access was not enabled. After allowing access, quit and reopen Bobrshot."
            )
            presentPermissionDeniedAlert()
            return false
        }
        operationStatus = .idle
        return true
    }

    private func presentPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Access Required"
        alert.informativeText =
            "Allow Bobrshot to capture your screen in System Settings, then quit and reopen Bobrshot."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }

    private func openScreenRecordingSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}

enum BobrshotApplicationError: Error, LocalizedError {
    case servicesUnavailable

    var errorDescription: String? {
        "Bobrshot could not initialize its capture services."
    }
}
