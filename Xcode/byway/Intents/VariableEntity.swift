import AppIntents
import Foundation

struct VariableEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "byway Variable"
    static let defaultQuery = VariableQuery()

    var id: UUID
    var key: String
    var kind: VariableKind

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(key)",
            subtitle: "\(kind.title)",
            image: .init(systemName: kind.symbol)
        )
    }

    init(_ variable: GlobalVariable) {
        id = variable.id
        key = variable.key
        kind = variable.value.kind
    }
}

struct VariableQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [VariableEntity] {
        try await VariableRepository.shared
            .list(includeExpired: false)
            .filter { identifiers.contains($0.id) }
            .map(VariableEntity.init)
    }

    func entities(matching string: String) async throws -> [VariableEntity] {
        try await VariableRepository.shared
            .list(matching: string)
            .map(VariableEntity.init)
    }

    func suggestedEntities() async throws -> [VariableEntity] {
        try await VariableRepository.shared
            .list(includeExpired: false)
            .prefix(50)
            .map(VariableEntity.init)
    }
}

struct VariableFolderEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "byway Folder"
    static let defaultQuery = VariableFolderQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "folder"))
    }

    init(_ folder: VariableFolder) {
        id = folder.id
        name = folder.name
    }
}

struct VariableFolderQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [VariableFolderEntity] {
        try await VariableRepository.shared.listFolders()
            .filter { identifiers.contains($0.id) }
            .map(VariableFolderEntity.init)
    }

    func entities(matching string: String) async throws -> [VariableFolderEntity] {
        try await VariableRepository.shared.listFolders()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(VariableFolderEntity.init)
    }

    func suggestedEntities() async throws -> [VariableFolderEntity] {
        try await VariableRepository.shared.listFolders().map(VariableFolderEntity.init)
    }
}

enum ImportMode: String, AppEnum {
    case keepExisting
    case overwrite
    case replaceAll

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Import Mode"
    static let caseDisplayRepresentations: [ImportMode: DisplayRepresentation] = [
        .keepExisting: "Keep Existing",
        .overwrite: "Overwrite Matching Keys",
        .replaceAll: "Replace Everything"
    ]

    var strategy: ImportStrategy {
        switch self {
        case .keepExisting: .keepExisting
        case .overwrite: .overwrite
        case .replaceAll: .replaceAll
        }
    }
}
