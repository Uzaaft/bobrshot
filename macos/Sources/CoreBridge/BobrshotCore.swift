import BobrshotKit

struct CoreVersion: CustomStringConvertible, Equatable, Sendable {
    let major: UInt16
    let minor: UInt16
    let patch: UInt16

    var description: String {
        "v\(major).\(minor).\(patch)"
    }
}

enum BobrshotCore {
    static var version: CoreVersion {
        let version = bobrshot_core_version()
        return CoreVersion(
            major: version.major,
            minor: version.minor,
            patch: version.patch
        )
    }
}
