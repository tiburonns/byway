import Foundation
import UniformTypeIdentifiers

struct BywayArchive: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var exportedAt: Date = .now
    var variables: [GlobalVariable]
    var attachments: [String: Data]
}

extension UTType {
    static let bywayArchive = UTType(exportedAs: "com.tiburonns.byway.archive")
}
