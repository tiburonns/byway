import AppIntents
import Foundation

private enum EntityIdentifier {
    static func encode(_ components: [String]) -> String {
        guard let data = try? JSONEncoder().encode(components) else { return "invalid" }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ identifier: String) -> [String]? {
        var base64 = identifier.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}

struct DictionaryEntryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DictionaryEntryEntity] {
        var entities: [DictionaryEntryEntity] = []
        for identifier in identifiers {
            guard let components = EntityIdentifier.decode(identifier),
                  components.count == 3, components[0] == "dictionary",
                  let variable = try? await VariableRepository.shared.variable(forKey: components[1]),
                  case .dictionary = variable.value else { continue }
            let value = try variable.value.value(atPath: components[2])
            entities.append(.init(variableKey: components[1], path: components[2], value: value))
        }
        return entities
    }
}
struct LocationDetailsQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LocationDetailsEntity] {
        var entities: [LocationDetailsEntity] = []
        for identifier in identifiers {
            guard let components = EntityIdentifier.decode(identifier),
                  components.count == 2, components[0] == "location",
                  let variable = try? await VariableRepository.shared.variable(forKey: components[1]),
                  case .location(let location) = variable.value else { continue }
            entities.append(try .init(variableKey: variable.key, location: location))
        }
        return entities
    }
}
struct MeasurementDetailsQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MeasurementDetailsEntity] {
        var entities: [MeasurementDetailsEntity] = []
        for identifier in identifiers {
            guard let components = EntityIdentifier.decode(identifier),
                  components.count == 2, components[0] == "measurement",
                  let variable = try? await VariableRepository.shared.variable(forKey: components[1]),
                  case .measurement(let measurement) = variable.value else { continue }
            entities.append(.init(variableKey: variable.key, measurement: measurement))
        }
        return entities
    }
}
struct VariableMetadataQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [VariableMetadataEntity] {
        var entities: [VariableMetadataEntity] = []
        for identifier in identifiers {
            guard let components = EntityIdentifier.decode(identifier),
                  components.count == 2, components[0] == "metadata" else { continue }
            let variable = try? await VariableRepository.shared.variable(forKey: components[1], includeExpired: true)
            entities.append(.init(key: components[1], variable: variable))
        }
        return entities
    }
}
struct BywayEventQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BywayEventEntity] {
        var entities: [BywayEventEntity] = []
        for identifier in identifiers {
            guard let components = EntityIdentifier.decode(identifier),
                  components.count == 3, components[0] == "event",
                  let eventID = UUID(uuidString: components[2]) else { continue }
            let events = try await VariableRepository.shared.queryEvents(key: components[1], limit: 1_000)
            if let event = events.first(where: { $0.id == eventID }) {
                entities.append(.init(event, key: components[1]))
            }
        }
        return entities
    }
}
struct ListItemQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ListItemEntity] {
        var entities: [ListItemEntity] = []
        for identifier in identifiers {
            guard let components = EntityIdentifier.decode(identifier),
                  components.count == 3, components[0] == "list",
                  let index = Int(components[2]), index >= 0,
                  let variable = try? await VariableRepository.shared.variable(forKey: components[1]),
                  case .array(let values) = variable.value,
                  values.indices.contains(index) else { continue }
            entities.append(.init(listKey: variable.key, index: index, value: values[index]))
        }
        return entities
    }
}
struct TransactionResultQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TransactionResultEntity] {
        identifiers.compactMap { identifier in
            guard let components = EntityIdentifier.decode(identifier),
                  components.count >= 6, components[0] == "transaction",
                  let created = Int(components[1]), let updated = Int(components[2]),
                  let deleted = Int(components[3]), let skipped = Int(components[4]) else { return nil }
            return TransactionResultEntity(.init(
                affectedKeys: Array(components.dropFirst(5)),
                createdCount: created,
                updatedCount: updated,
                deletedCount: deleted,
                skippedCount: skipped
            ))
        }
    }
}

struct DictionaryEntryEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dictionary Entry"
    static let defaultQuery = DictionaryEntryQuery()

    var id: String
    @Property(title: "Variable Key") var variableKey: String
    @Property(title: "Path") var path: String
    @Property(title: "Exists") var exists: Bool
    @Property(title: "Is Null") var isNull: Bool
    @Property(title: "Type") var type: String
    @Property(title: "JSON") var json: String
    @Property(title: "Text") var text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(variableKey).\(path)",
            subtitle: exists ? "\(type)" : "Missing",
            image: .init(systemName: exists ? "curlybraces" : "questionmark.diamond")
        )
    }

    init(variableKey: String, path: String, value: VariableValue?) {
        id = EntityIdentifier.encode(["dictionary", variableKey, path])
        self.variableKey = variableKey
        self.path = path
        exists = value != nil
        isNull = value?.kind == .null
        type = value?.kind.title ?? "Missing"
        json = value?.jsonString ?? ""
        text = value.map(IntentSupport.plainText) ?? ""
    }
}

struct LocationDetailsEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Location Details"
    static let defaultQuery = LocationDetailsQuery()

    var id: String
    @Property(title: "Variable Key") var variableKey: String
    @Property(title: "Latitude") var latitude: Double
    @Property(title: "Longitude") var longitude: Double
    @Property(title: "Name") var name: String?
    @Property(title: "Altitude") var altitude: Double?
    @Property(title: "Horizontal Accuracy") var horizontalAccuracy: Double?
    @Property(title: "Maps URL") var mapsURL: URL

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name ?? variableKey)",
            subtitle: "\(latitude), \(longitude)",
            image: .init(systemName: "location.fill")
        )
    }

    init(variableKey: String, location: BywayLocation) throws {
        id = EntityIdentifier.encode(["location", variableKey])
        self.variableKey = variableKey
        latitude = location.latitude
        longitude = location.longitude
        name = location.name
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        mapsURL = try IntentSupport.mapsURL(for: location)
    }
}

struct MeasurementDetailsEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Measurement Details"
    static let defaultQuery = MeasurementDetailsQuery()

    var id: String
    @Property(title: "Variable Key") var variableKey: String
    @Property(title: "Value") var value: Double
    @Property(title: "Unit") var unit: String
    @Property(title: "Formatted Value") var formattedValue: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(formattedValue)",
            subtitle: "\(variableKey)",
            image: .init(systemName: "ruler")
        )
    }

    init(variableKey: String, measurement: BywayMeasurement) {
        id = EntityIdentifier.encode(["measurement", variableKey])
        self.variableKey = variableKey
        value = measurement.value
        unit = measurement.unitSymbol
        formattedValue = "\(measurement.value) \(measurement.unitSymbol)"
    }
}

struct VariableMetadataEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Variable Metadata"
    static let defaultQuery = VariableMetadataQuery()

    var id: String
    @Property(title: "Key") var key: String
    @Property(title: "Exists") var exists: Bool
    @Property(title: "Is Null") var isNull: Bool
    @Property(title: "Type") var type: String
    @Property(title: "Created At") var createdAt: Date?
    @Property(title: "Updated At") var updatedAt: Date?
    @Property(title: "Expires At") var expiresAt: Date?
    @Property(title: "Is Expired") var isExpired: Bool
    @Property(title: "Tags") var tags: [String]
    @Property(title: "Revision") var revision: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(key)",
            subtitle: exists ? "\(type) · revision \(revision)" : "Missing",
            image: .init(systemName: exists ? "info.circle" : "questionmark.diamond")
        )
    }

    init(key: String, variable: GlobalVariable?) {
        id = EntityIdentifier.encode(["metadata", variable?.key ?? key])
        self.key = variable?.key ?? key
        exists = variable != nil
        isNull = variable?.value.kind == .null
        type = variable?.value.kind.title ?? "Missing"
        createdAt = variable?.createdAt
        updatedAt = variable?.updatedAt
        expiresAt = variable?.expiresAt
        isExpired = variable?.isExpired ?? false
        tags = variable?.tags ?? []
        revision = variable?.revision ?? 0
    }
}

struct BywayEventEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "byway Event"
    static let defaultQuery = BywayEventQuery()

    var id: String
    @Property(title: "UUID") var uuid: String
    @Property(title: "Category") var category: String
    @Property(title: "Action") var action: String
    @Property(title: "Date") var date: Date
    @Property(title: "Details JSON") var detailsJSON: String
    @Property(title: "Event JSON") var eventJSON: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(category): \(action)",
            subtitle: "\(date.formatted(date: .abbreviated, time: .shortened))",
            image: .init(systemName: "clock.arrow.circlepath")
        )
    }

    init(_ event: BywayEvent, key: String = "HISTORY.Events") {
        id = EntityIdentifier.encode(["event", key, event.id.uuidString])
        uuid = event.id.uuidString
        category = event.category
        action = event.action
        date = event.timestamp
        detailsJSON = VariableValue.dictionary(event.details).jsonString
        eventJSON = event.variableValue.jsonString
    }
}

struct ListItemEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List Item"
    static let defaultQuery = ListItemQuery()

    var id: String
    @Property(title: "List Key") var listKey: String
    @Property(title: "Index") var index: Int
    @Property(title: "Type") var type: String
    @Property(title: "JSON") var json: String
    @Property(title: "Text") var text: String
    @Property(title: "Is Null") var isNull: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Item \(index)",
            subtitle: "\(text)",
            image: .init(systemName: "list.number")
        )
    }

    init(listKey: String, index: Int, value: VariableValue) {
        id = EntityIdentifier.encode(["list", listKey, String(index)])
        self.listKey = listKey
        self.index = index
        type = value.kind.title
        json = value.jsonString
        text = IntentSupport.plainText(for: value)
        isNull = value.kind == .null
    }
}

struct TransactionResultEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction Result"
    static let defaultQuery = TransactionResultQuery()

    var id: String
    @Property(title: "Affected Keys") var affectedKeys: [String]
    @Property(title: "Created") var created: Int
    @Property(title: "Updated") var updated: Int
    @Property(title: "Deleted") var deleted: Int
    @Property(title: "Skipped") var skipped: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(affectedKeys.count) variables changed",
            subtitle: "\(created) created, \(updated) updated, \(deleted) deleted",
            image: .init(systemName: "checkmark.shield")
        )
    }

    init(_ summary: TransactionSummary) {
        id = EntityIdentifier.encode([
            "transaction",
            String(summary.createdCount),
            String(summary.updatedCount),
            String(summary.deletedCount),
            String(summary.skippedCount)
        ] + summary.affectedKeys)
        affectedKeys = summary.affectedKeys
        created = summary.createdCount
        updated = summary.updatedCount
        deleted = summary.deletedCount
        skipped = summary.skippedCount
    }
}

enum EventOrder: String, AppEnum {
    case newestFirst
    case oldestFirst

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Event Order"
    static let caseDisplayRepresentations: [EventOrder: DisplayRepresentation] = [
        .newestFirst: "Newest First",
        .oldestFirst: "Oldest First"
    ]
}

enum ListSortOrder: String, AppEnum {
    case ascending
    case descending

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sort Order"
    static let caseDisplayRepresentations: [ListSortOrder: DisplayRepresentation] = [
        .ascending: "Ascending",
        .descending: "Descending"
    ]
}
