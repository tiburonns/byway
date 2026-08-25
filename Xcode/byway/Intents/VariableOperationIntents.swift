import AppIntents
import Foundation

struct DeleteVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete Variable"
    static let description = IntentDescription("Delete a persistent variable by key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await VariableRepository.shared.delete(key: key)
        return .result(dialog: "Deleted \(key).")
    }
}

struct VariableExistsIntent: AppIntent {
    static let title: LocalizedStringResource = "Variable Exists"
    static let description = IntentDescription("Check whether a non-expired variable exists.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let exists = (try? await VariableRepository.shared.variable(forKey: key)) != nil
        return .result(value: exists)
    }
}

struct ToggleVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Boolean Variable"
    static let description = IntentDescription("Invert a stored Boolean and return its new value.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let value = try await VariableRepository.shared.toggle(key: key)
        return .result(value: value, dialog: "\(key) is now \(value ? "true" : "false").")
    }
}

struct IncrementVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Increment Number Variable"
    static let description = IntentDescription("Atomically add an amount to an integer or decimal variable.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Amount", default: 1) var amount: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Increment \(.$key) by \(.$amount)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let value = try await VariableRepository.shared.increment(key: key, by: amount)
        return .result(value: value, dialog: "\(key) is now \(value).")
    }
}

struct AppendToListVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Append to List Variable"
    static let description = IntentDescription("Append text items to an existing persistent list.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(
        title: "Items",
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var items: [String]

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let values = try await VariableRepository.shared.append(
            key: key,
            values: items.map(VariableValue.text)
        )
        let result = values.map(IntentSupport.plainText)
        return .result(value: result, dialog: "Added \(items.count) items to \(key).")
    }
}

struct ListVariableKeysIntent: AppIntent {
    static let title: LocalizedStringResource = "List Variable Keys"
    static let description = IntentDescription("Return all non-expired variable keys, optionally filtered by text or tag.")
    static let openAppWhenRun = false

    @Parameter(title: "Search") var search: String?
    @Parameter(title: "Tag") var tag: String?

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let variables = try await VariableRepository.shared.list(
            matching: search ?? "",
            tag: tag
        )
        let keys = variables.map(\.key)
        return .result(value: keys, dialog: "Found \(keys.count) variables.")
    }
}

struct RemoveExpiredVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Expired Variables"
    static let description = IntentDescription("Delete every variable whose expiration date has passed.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let count = try await VariableRepository.shared.removeExpired()
        return .result(value: count, dialog: "Removed \(count) expired variables.")
    }
}

struct RenameVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Rename Variable"
    static let description = IntentDescription("Rename a variable while preserving its value and metadata.")
    static let openAppWhenRun = false

    @Parameter(title: "Variable") var variable: VariableEntity
    @Parameter(title: "New Key") var newKey: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let renamed = try await VariableRepository.shared.rename(id: variable.id, to: newKey)
        return .result(value: renamed.key, dialog: "Renamed \(variable.key) to \(renamed.key).")
    }
}

struct SetDictionaryEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Dictionary Entry"
    static let description = IntentDescription("Set one field in a stored dictionary using a JSON value.")
    static let openAppWhenRun = false

    @Parameter(title: "Variable Key") var key: String
    @Parameter(title: "Field") var field: String
    @Parameter(title: "JSON Value") var jsonValue: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let value = try VariableValue.fromJSON(jsonValue)
        let result = try await VariableRepository.shared.setDictionaryEntry(key: key, field: field, value: value)
        let json = VariableValue.dictionary(result).jsonString
        return .result(value: json, dialog: "Updated \(field) in \(key).")
    }
}

struct RemoveDictionaryEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Dictionary Entry"
    static let description = IntentDescription("Remove one field from a stored dictionary.")
    static let openAppWhenRun = false

    @Parameter(title: "Variable Key") var key: String
    @Parameter(title: "Field") var field: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await VariableRepository.shared.removeDictionaryEntry(key: key, field: field)
        let json = VariableValue.dictionary(result).jsonString
        return .result(value: json, dialog: "Removed \(field) from \(key).")
    }
}
