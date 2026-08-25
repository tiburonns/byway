import Foundation

struct GlobalVariable: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var key: String
    var value: VariableValue
    var tags: [String]
    var notes: String
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    var revision: Int

    init(
        id: UUID = UUID(),
        key: String,
        value: VariableValue,
        tags: [String] = [],
        notes: String = "",
        isFavorite: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        expiresAt: Date? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.tags = tags
        self.notes = notes
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.revision = revision
    }

    var isExpired: Bool {
        expiresAt.map { $0 <= .now } ?? false
    }
}

enum ChangeOperation: String, Codable, Sendable {
    case create
    case update
    case delete
    case restore
    case importVariables
}

struct VariableChange: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var variableID: UUID
    var key: String
    var operation: ChangeOperation
    var timestamp: Date
    var previous: GlobalVariable?
    var current: GlobalVariable?

    init(
        id: UUID = UUID(),
        variableID: UUID,
        key: String,
        operation: ChangeOperation,
        timestamp: Date = .now,
        previous: GlobalVariable?,
        current: GlobalVariable?
    ) {
        self.id = id
        self.variableID = variableID
        self.key = key
        self.operation = operation
        self.timestamp = timestamp
        self.previous = previous
        self.current = current
    }
}

struct StoreEnvelope: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var updatedAt: Date = .now
    var variables: [GlobalVariable] = []
    var history: [VariableChange] = []
}

enum ImportStrategy: String, CaseIterable, Identifiable, Sendable {
    case keepExisting
    case overwrite
    case replaceAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepExisting: "Keep existing"
        case .overwrite: "Overwrite matching keys"
        case .replaceAll: "Replace everything"
        }
    }
}

enum BywayError: LocalizedError, Sendable {
    case emptyKey
    case duplicateKey(String)
    case notFound(String)
    case typeMismatch(expected: VariableKind, actual: VariableKind)
    case invalidValue(String)
    case missingFile(String)
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyKey: "The variable key cannot be empty."
        case .duplicateKey(let key): "A variable named \(key) already exists."
        case .notFound(let key): "No variable named \(key) was found."
        case .typeMismatch(let expected, let actual):
            "Expected \(expected.title), but the variable contains \(actual.title)."
        case .invalidValue(let message): message
        case .missingFile(let name): "The stored file \(name) is unavailable."
        case .storageUnavailable: "The byway storage location is unavailable."
        }
    }
}
