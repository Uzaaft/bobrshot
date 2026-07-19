import Foundation

@MainActor
final class BobrshotServiceContainer {
    let paths: ApplicationDataPaths
    let historyStore: CaptureHistoryStore
    let screenshots: ScreenshotWorkflowService
    let recordings: RecordingWorkflowService

    init(
        fileManager: FileManager = .default,
        maximumHistoryCount: Int = 100
    ) throws {
        let paths = try ApplicationDataPaths.resolve(fileManager: fileManager)
        try paths.prepare(fileManager: fileManager)
        let historyStore = try CaptureHistoryStore(
            directory: paths.state,
            maximumEntryCount: maximumHistoryCount
        )

        self.paths = paths
        self.historyStore = historyStore
        screenshots = ScreenshotWorkflowService(historyStore: historyStore)
        recordings = RecordingWorkflowService(historyStore: historyStore)
    }
}
