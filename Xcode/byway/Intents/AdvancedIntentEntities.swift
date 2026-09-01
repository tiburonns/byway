import AppIntents
import Foundation

struct DictionaryEntryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DictionaryEntryEntity] { [] }
}
struct LocationDetailsQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LocationDetailsEntity] { [] }
}
struct MeasurementDetailsQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MeasurementDetailsEntity] { [] }
}
struct VariableMetadataQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [VariableMetadataEntity] { [] }
}
struct BywayEventQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BywayEventEntity] { [] }
}
struct ListItemQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ListItemEntity] { [] }
}
struct TransactionResultQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TransactionResultEntity] { [] }
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
        id = UUID().uuidString
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
        id = UUID().uuidString
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
        id = UUID().uuidString
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
        id = variable?.id.uuidString ?? UUID().uuidString
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

    init(_ event: BywayEvent) {
        id = event.id.uuidString
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
        id = "\(listKey):\(index):\(UUID().uuidString)"
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
        id = UUID().uuidString
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
