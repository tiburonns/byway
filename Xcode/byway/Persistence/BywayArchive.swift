import Foundation
import UniformTypeIdentifiers

struct ArchivePreview: Sendable {
    var archiveVersion: Int
    var totalVariables: Int
    var variablesToImport: Int
    var skippedExisting: Int
    var overwrittenExisting: Int
    var removedExisting: Int
    var attachments: Int
    var folders: Int
    var attachmentBytes: Int
    var isEncrypted: Bool
}

struct BywayEncryptedArchive: Codable, Sendable {
    static let format = "byway-encrypted-archive"
    static let currentVersion = 2
    static let pbkdf2SHA256 = "pbkdf2-hmac-sha256"

    var format = Self.format
    var version = Self.currentVersion
    var kdf: String? = Self.pbkdf2SHA256
    var salt: Data
    var iterations: Int
    var sealedArchive: Data

    init(
        format: String = Self.format,
        version: Int = Self.currentVersion,
        kdf: String? = Self.pbkdf2SHA256,
        salt: Data,
        iterations: Int,
        sealedArchive: Data
    ) {
        self.format = format
        self.version = version
        self.kdf = kdf
        self.salt = salt
        self.iterations = iterations
        self.sealedArchive = sealedArchive
    }
}

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
    static let bywayEncryptedArchive = UTType(exportedAs: "com.tiburonns.byway.encrypted-archive", conformingTo: .data)
}
