import CryptoKit
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


enum BywayArchiveCrypto {
    static func pbkdf2SHA256Data(
        passphrase: String,
        salt: Data,
        iterations: Int,
        keyLength: Int = 32
    ) -> Data {
        precondition(iterations > 0)
        precondition(keyLength > 0)

        let passwordKey = SymmetricKey(data: Data(passphrase.utf8))
        var output = Data()
        var blockIndex: UInt32 = 1

        while output.count < keyLength {
            var bigEndianBlock = blockIndex.bigEndian
            var initial = Data()
            initial.append(salt)
            withUnsafeBytes(of: &bigEndianBlock) {
                initial.append(contentsOf: $0)
            }

            var u = Data(
                HMAC<SHA256>.authenticationCode(
                    for: initial,
                    using: passwordKey
                )
            )
            var block = u

            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(
                        HMAC<SHA256>.authenticationCode(
                            for: u,
                            using: passwordKey
                        )
                    )
                    for index in block.indices {
                        block[index] ^= u[index]
                    }
                }
            }

            output.append(block)
            blockIndex &+= 1
        }

        return output.prefix(keyLength)
    }

    static func pbkdf2SHA256Key(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) -> SymmetricKey {
        SymmetricKey(
            data: pbkdf2SHA256Data(
                passphrase: passphrase,
                salt: salt,
                iterations: iterations
            )
        )
    }

    static func legacyKey(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) -> SymmetricKey {
        let password = Data(passphrase.utf8)
        var material = salt + password
        var digest = Data(SHA256.hash(data: material))

        if iterations > 1 {
            for _ in 1..<iterations {
                material.removeAll(keepingCapacity: true)
                material.append(digest)
                material.append(salt)
                material.append(password)
                digest = Data(SHA256.hash(data: material))
            }
        }

        return SymmetricKey(data: digest)
    }
}
