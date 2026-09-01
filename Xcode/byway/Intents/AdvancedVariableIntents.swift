import AppIntents
import Foundation

struct GetDictionaryEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Dictionary Entry"
    static let description = IntentDescription("Read a dictionary value by a dot-separated path and distinguish missing from null.")
    static let openAppWhenRun = false

    @Parameter(title: "Variable Key") var key: String
    @Parameter(title: "Path") var path: String

    func perform() async throws -> some IntentResult & ReturnsValue<DictionaryEntryEntity> & ProvidesDialog {
        let value = try await VariableRepository.shared.dictionaryEntry(key: key, path: path)
        let result = DictionaryEntryEntity(variableKey: key, path: path, value: value)
        return .result(
            value: result,
            dialog: value == nil ? "No entry exists at \(path)." : "Retrieved \(path) from \(key)."
        )
    }
}

struct DictionaryEntryExistsIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictionary Entry Exists"
    static let description = IntentDescription("Check whether a dot-separated dictionary path exists. Null values count as existing.")
    static let openAppWhenRun = false

    @Parameter(title: "Variable Key") var key: String
    @Parameter(title: "Path") var path: String

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: try await VariableRepository.shared.dictionaryEntry(key: key, path: path) != nil)
    }
}

struct AppendJSONToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Append JSON to List"
    static let description = IntentDescription("Append a JSON object, array, primitive, or null to an existing list.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String
    @Parameter(title: "JSON", inputConnectionBehavior: .connectToPreviousIntentResult) var json: String

    func perform() async throws -> some IntentResult & ReturnsValue<ListItemEntity> & ProvidesDialog {
        let value = try IntentSupport.jsonValue(from: json)
        let values = try await VariableRepository.shared.append(key: key, values: [value])
        return .result(
            value: ListItemEntity(listKey: key, index: values.count - 1, value: value),
            dialog: "Added one JSON item to \(key)."
        )
    }
}

struct AppendEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Append Event"
    static let description = IntentDescription("Append a structured event with an automatic UUID to HISTORY.Events or another list.")
    static let openAppWhenRun = false

    @Parameter(title: "Events Key", default: "HISTORY.Events") var key: String
    @Parameter(title: "Category") var category: String
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Details JSON") var detailsJSON: String?
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "UUID") var uuid: String?

    func perform() async throws -> some IntentResult & ReturnsValue<BywayEventEntity> & ProvidesDialog {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategory.isEmpty, !trimmedAction.isEmpty else {
            throw BywayError.invalidValue("Category and action cannot be empty.")
        }
        let detailsValue = try detailsJSON.map(IntentSupport.jsonValue) ?? .dictionary([:])
        guard case .dictionary(let details) = detailsValue else {
            throw BywayError.invalidValue("Event details must be a JSON object.")
        }
        let eventID: UUID
        if let uuid, !uuid.isEmpty {
            guard let parsed = UUID(uuidString: uuid) else {
                throw BywayError.invalidValue("The supplied event UUID is invalid.")
            }
            eventID = parsed
        } else {
            eventID = UUID()
        }
        let event = BywayEvent(
            id: eventID,
            category: trimmedCategory,
            action: trimmedAction,
            timestamp: date ?? .now,
            details: details
        )
        _ = try await VariableRepository.shared.appendEvent(key: key, event: event)
        return .result(value: BywayEventEntity(event), dialog: "Added \(trimmedCategory) event \(eventID.uuidString).")
    }
}

/// Records a complete mode change without exposing timestamps or bookkeeping
/// fields to Shortcuts. Keeping Date.now and the event UUID inside the intent
/// prevents Siri from treating them as values that need user confirmation.
struct SetSystemModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set System Mode"
    static let description = IntentDescription("Set Byway's active mode and automatically record when and how it changed.")
    static let openAppWhenRun = false

    @Parameter(title: "Mode") var mode: String
    @Parameter(title: "Source", default: "SIRI") var source: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set system mode to \(\.$mode) from \(\.$source)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let normalizedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMode.isEmpty else {
            throw BywayError.invalidValue("Mode cannot be empty.")
        }
        guard !normalizedSource.isEmpty else {
            throw BywayError.invalidValue("Source cannot be empty.")
        }

        let now = Date.now
        let event = BywayEvent(
            id: UUID(),
            category: "SYS",
            action: "MODE_CHANGE",
            timestamp: now,
            details: [
                "to": .text(normalizedMode),
                "source": .text(normalizedSource)
            ]
        )
        _ = try await VariableRepository.shared.applyTransaction([
            .set(key: "SYS.Mode", value: .text(normalizedMode), expiresAt: nil),
            .set(key: "SYS.ModeChangedAt", value: .date(now), expiresAt: nil),
            .set(key: "SYS.LastAction", value: .text("MODE_CHANGE"), expiresAt: nil),
            .set(key: "SYS.LastActionAt", value: .date(now), expiresAt: nil),
            .set(key: "SYS.LastSource", value: .text(normalizedSource), expiresAt: nil),
            .append(key: "HISTORY.Events", values: [event.variableValue])
        ])
        return .result(value: normalizedMode, dialog: "Modo \(normalizedMode) activado.")
    }
}

struct QueryEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "Query Events"
    static let description = IntentDescription("Filter structured events by category, action, date range, limit, and order.")
    static let openAppWhenRun = false

    @Parameter(title: "Events Key", default: "HISTORY.Events") var key: String
    @Parameter(title: "Category") var category: String?
    @Parameter(title: "Action") var action: String?
    @Parameter(title: "From Date") var startDate: Date?
    @Parameter(title: "Through Date") var endDate: Date?
    @Parameter(title: "Limit", default: 50) var limit: Int
    @Parameter(title: "Order", default: .newestFirst) var order: EventOrder

    func perform() async throws -> some IntentResult & ReturnsValue<[BywayEventEntity]> & ProvidesDialog {
        guard limit >= 0 else { throw BywayError.invalidValue("Limit cannot be negative.") }
        if let startDate, let endDate, startDate > endDate {
            throw BywayError.invalidValue("From Date must be before Through Date.")
        }
        let events = try await VariableRepository.shared.queryEvents(
            key: key,
            category: category,
            action: action,
            from: startDate,
            through: endDate,
            limit: limit,
            newestFirst: order == .newestFirst
        )
        return .result(value: events.map(BywayEventEntity.init), dialog: "Found \(events.count) events.")
    }
}

struct GetLastEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Event"
    static let description = IntentDescription("Return the newest event matching an optional category and action.")
    static let openAppWhenRun = false

    @Parameter(title: "Events Key", default: "HISTORY.Events") var key: String
    @Parameter(title: "Category") var category: String?
    @Parameter(title: "Action") var action: String?

    func perform() async throws -> some IntentResult & ReturnsValue<BywayEventEntity> & ProvidesDialog {
        let event = try await VariableRepository.shared.lastEvent(key: key, category: category, action: action)
        return .result(value: BywayEventEntity(event), dialog: "Retrieved the latest \(event.category) event.")
    }
}

struct GetLocationDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Location Details"
    static let description = IntentDescription("Return latitude, longitude, name, altitude, accuracy, and Maps URL separately.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<LocationDetailsEntity> {
        let variable = try await IntentSupport.variable(key: key, expected: .location)
        guard case .location(let location) = variable.value else {
            throw BywayError.invalidValue("Invalid location value.")
        }
        return .result(value: try LocationDetailsEntity(variableKey: variable.key, location: location))
    }
}

struct GetMeasurementDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Measurement Details"
    static let description = IntentDescription("Return a measurement's numeric value and unit separately.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<MeasurementDetailsEntity> {
        let variable = try await IntentSupport.variable(key: key, expected: .measurement)
        guard case .measurement(let measurement) = variable.value else {
            throw BywayError.invalidValue("Invalid measurement value.")
        }
        return .result(value: MeasurementDetailsEntity(variableKey: variable.key, measurement: measurement))
    }
}

struct BatchSetVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Batch Set Variables"
    static let description = IntentDescription("Atomically set multiple variables from one JSON object. Supports typed JSON envelopes.")
    static let openAppWhenRun = false

    @Parameter(title: "Variables JSON", inputConnectionBehavior: .connectToPreviousIntentResult) var json: String
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<TransactionResultEntity> & ProvidesDialog {
        let mutations = try IntentSupport.batchMutations(from: json, expiresAt: expiresAt)
        let summary = try await VariableRepository.shared.applyTransaction(mutations)
        return .result(
            value: TransactionResultEntity(summary),
            dialog: "Updated \(summary.affectedKeys.count) variables atomically."
        )
    }
}

struct RunVariableTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Variable Transaction"
    static let description = IntentDescription("Apply set, ensure, delete, append, and dictionary operations together with rollback on failure.")
    static let openAppWhenRun = false

    @Parameter(title: "Operations JSON", inputConnectionBehavior: .connectToPreviousIntentResult) var json: String

    func perform() async throws -> some IntentResult & ReturnsValue<TransactionResultEntity> & ProvidesDialog {
        let mutations = try IntentSupport.transactionMutations(from: json)
        let summary = try await VariableRepository.shared.applyTransaction(mutations)
        return .result(
            value: TransactionResultEntity(summary),
            dialog: "Transaction committed for \(summary.affectedKeys.count) variables."
        )
    }
}

struct GenerateUUIDIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate UUID"
    static let description = IntentDescription("Generate a new random UUID for a trip, parking session, song, or event.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: UUID().uuidString)
    }
}

struct CountListItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Count List Items"
    static let description = IntentDescription("Return the number of items in a stored list.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: try await VariableRepository.shared.listCount(key: key))
    }
}

struct FindListItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find List Items"
    static let description = IntentDescription("Find list items by whole JSON value or by a dot-separated field path.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String
    @Parameter(title: "Field Path") var path: String?
    @Parameter(title: "Equals JSON") var equalsJSON: String?
    @Parameter(title: "Limit", default: 100) var limit: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[ListItemEntity]> & ProvidesDialog {
        let expected = try equalsJSON.map(IntentSupport.jsonValue)
        let items = try await VariableRepository.shared.findListItems(
            key: key,
            path: path?.isEmpty == false ? path : nil,
            equalTo: expected,
            limit: limit
        )
        return .result(
            value: items.map { ListItemEntity(listKey: key, index: $0.index, value: $0.value) },
            dialog: "Found \(items.count) list items."
        )
    }
}

struct UpdateListItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Update List Item"
    static let description = IntentDescription("Replace one list item by its zero-based index using JSON.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String
    @Parameter(title: "Index") var index: Int
    @Parameter(title: "JSON Value") var json: String

    func perform() async throws -> some IntentResult & ReturnsValue<ListItemEntity> & ProvidesDialog {
        let value = try IntentSupport.jsonValue(from: json)
        _ = try await VariableRepository.shared.updateListItem(key: key, index: index, value: value)
        return .result(
            value: ListItemEntity(listKey: key, index: index, value: value),
            dialog: "Updated item \(index) in \(key)."
        )
    }
}

struct DeleteListItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete List Item"
    static let description = IntentDescription("Delete one list item by its zero-based index.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String
    @Parameter(title: "Index") var index: Int

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let values = try await VariableRepository.shared.deleteListItem(key: key, index: index)
        return .result(value: values.count, dialog: "Deleted item \(index); \(values.count) items remain.")
    }
}

struct SortListIntent: AppIntent {
    static let title: LocalizedStringResource = "Sort List"
    static let description = IntentDescription("Sort a list by each item or by a dot-separated field path.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String
    @Parameter(title: "Field Path") var path: String?
    @Parameter(title: "Order", default: .ascending) var order: ListSortOrder

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let values = try await VariableRepository.shared.sortList(
            key: key,
            path: path?.isEmpty == false ? path : nil,
            ascending: order == .ascending
        )
        return .result(value: values.map(\.jsonString), dialog: "Sorted \(values.count) items in \(key).")
    }
}

struct RemoveDuplicateListItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Duplicate List Items"
    static let description = IntentDescription("Remove duplicate list values while preserving the first occurrence.")
    static let openAppWhenRun = false

    @Parameter(title: "List Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let before = try await VariableRepository.shared.listCount(key: key)
        let values = try await VariableRepository.shared.removeDuplicateListItems(key: key)
        return .result(value: values.count, dialog: "Removed \(before - values.count) duplicate items.")
    }
}

struct GetVariableMetadataIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Variable Metadata"
    static let description = IntentDescription("Return existence, null state, timestamps, type, tags, expiration, and revision.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<VariableMetadataEntity> {
        do {
            let variable = try await VariableRepository.shared.variable(forKey: key, includeExpired: true)
            return .result(value: VariableMetadataEntity(key: key, variable: variable))
        } catch BywayError.notFound {
            return .result(value: VariableMetadataEntity(key: key, variable: nil))
        }
    }
}

struct EnsureVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Initialize or Ensure Variable"
    static let description = IntentDescription("Create a variable from JSON only when the key does not already exist, including null variables.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Default JSON") var json: String
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<VariableMetadataEntity> & ProvidesDialog {
        let value = try IntentSupport.jsonValue(from: json)
        let result = try await VariableRepository.shared.ensure(key: key, value: value, expiresAt: expiresAt)
        return .result(
            value: VariableMetadataEntity(key: key, variable: result.variable),
            dialog: result.created ? "Created \(key)." : "\(key) already exists; its value was preserved."
        )
    }
}

struct CreateVariableFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Variable Folder"
    static let description = IntentDescription("Create an empty folder for organizing byway variables.")
    static let openAppWhenRun = false

    @Parameter(title: "Folder Name") var name: String

    func perform() async throws -> some IntentResult & ReturnsValue<VariableFolderEntity> & ProvidesDialog {
        let folder = try await VariableRepository.shared.createFolder(name: name)
        return .result(value: VariableFolderEntity(folder), dialog: "Created folder \(folder.name).")
    }
}

struct ListVariableFoldersIntent: AppIntent {
    static let title: LocalizedStringResource = "List Variable Folders"
    static let description = IntentDescription("Return every byway variable folder, including empty folders.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[VariableFolderEntity]> {
        let folders = try await VariableRepository.shared.listFolders()
        return .result(value: folders.map(VariableFolderEntity.init))
    }
}

struct MoveVariablesToFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Variables to Folder"
    static let description = IntentDescription("Move multiple byway variables to a folder. Leave Folder empty to remove them from folders.")
    static let openAppWhenRun = false

    @Parameter(title: "Variables") var variables: [VariableEntity]
    @Parameter(title: "Folder") var folder: VariableFolderEntity?

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard !variables.isEmpty else { throw BywayError.invalidValue("Select at least one variable.") }
        let count = try await VariableRepository.shared.moveVariables(
            ids: Set(variables.map(\.id)),
            to: folder?.id
        )
        let destination = folder?.name ?? "No Folder"
        return .result(value: count, dialog: "Moved \(count) variables to \(destination).")
    }
}

struct DeleteMultipleVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete Multiple Variables"
    static let description = IntentDescription("Delete multiple selected byway variables in one atomic operation.")
    static let openAppWhenRun = false

    @Parameter(title: "Variables") var variables: [VariableEntity]

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard !variables.isEmpty else { throw BywayError.invalidValue("Select at least one variable.") }
        let count = try await VariableRepository.shared.deleteVariables(ids: Set(variables.map(\.id)))
        return .result(value: count, dialog: "Deleted \(count) variables.")
    }
}

struct DeleteVariableFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete Variable Folder"
    static let description = IntentDescription("Delete a folder while keeping its variables in No Folder.")
    static let openAppWhenRun = false

    @Parameter(title: "Folder") var folder: VariableFolderEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await VariableRepository.shared.deleteFolder(id: folder.id)
        return .result(dialog: "Deleted folder \(folder.name). Its variables were kept.")
    }
}
