import Foundation

struct ApplicationDataPaths: Equatable, Sendable {
    let root: URL
    let screenshots: URL
    let recordings: URL
    let state: URL

    init(applicationSupportDirectory: URL) {
        root =
            applicationSupportDirectory
            .appendingPathComponent("Bobrshot", isDirectory: true)
        screenshots = root.appendingPathComponent("Screenshots", isDirectory: true)
        recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        state = root.appendingPathComponent("State", isDirectory: true)
    }

    static func resolve(fileManager: FileManager = .default) throws -> ApplicationDataPaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return ApplicationDataPaths(applicationSupportDirectory: applicationSupport)
    }

    func prepare(fileManager: FileManager = .default) throws {
        for directory in [root, screenshots, recordings, state] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
