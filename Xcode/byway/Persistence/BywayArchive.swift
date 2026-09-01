import Foundation
import UniformTypeIdentifiers

struct BywayArchive: Codable, Sendable {
    static let currentVersion = 2

    var version: Int = currentVersion
    var exportedAt: Date = .now
    var variables: [GlobalVariable]
    var attachments: [String: Data]
    var folders: [VariableFolder]

    init(
        version: Int = currentVersion,
        exportedAt: Date = .now,
        variables: [GlobalVariable],
        attachments: [String: Data],
        folders: [VariableFolder] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.variables = variables
        self.attachments = attachments
        self.folders = folders
    }

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, variables, attachments, folders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        variables = try container.decode([GlobalVariable].self, forKey: .variables)
        attachments = try container.decodeIfPresent([String: Data].self, forKey: .attachments) ?? [:]
        folders = try container.decodeIfPresent([VariableFolder].self, forKey: .folders) ?? []
    }
}

extension UTType {
    static let bywayArchive = UTType(exportedAs: "com.tiburonns.byway.archive", conformingTo: .json)
}
