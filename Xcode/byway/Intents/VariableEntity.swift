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
