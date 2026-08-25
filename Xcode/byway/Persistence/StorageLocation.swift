import Foundation

struct StorageStatus: Sendable {
    enum Location: String, Sendable {
        case iCloud
        case local
    }

    var location: Location
    var rootURL: URL
}

enum BywayStorage {
    static let iCloudContainerIdentifier = "iCloud.com.tiburonns.byway"

    static func localRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("byway", isDirectory: true)
    }

    static func preferredRoot() throws -> StorageStatus {
        if let container = FileManager.default.url(
            forUbiquityContainerIdentifier: iCloudContainerIdentifier
        ) {
            let root = container
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("byway", isDirectory: true)
            return StorageStatus(location: .iCloud, rootURL: root)
        }

        return StorageStatus(location: .local, rootURL: try localRoot())
    }
}
