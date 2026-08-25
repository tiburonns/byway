import AppIntents
import Foundation
import UniformTypeIdentifiers

struct SetTextVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Text Variable"
    static let description = IntentDescription("Store text under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(
        title: "Text",
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var value: String
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(.$key) to \(.$value)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(
            key: key,
            value: .text(value),
            expiresAt: expiresAt
        )
        return .result(value: value, dialog: "Saved \(key).")
    }
}

struct SetBooleanVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Boolean Variable"
    static let description = IntentDescription("Store a true or false value under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Value") var value: Bool
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(
            key: key,
            value: .boolean(value),
            expiresAt: expiresAt
        )
        return .result(value: value, dialog: "Saved \(key).")
    }
}

struct SetIntegerVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Integer Variable"
    static let description = IntentDescription("Store a whole number under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Integer") var value: Int
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(
            key: key,
            value: .integer(Int64(value)),
            expiresAt: expiresAt
        )
        return .result(value: value, dialog: "Saved \(key).")
    }
}

struct SetNumberVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Number Variable"
    static let description = IntentDescription("Store a decimal number under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Number") var value: Double
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(
            key: key,
            value: .number(value),
            expiresAt: expiresAt
        )
        return .result(value: value, dialog: "Saved \(key).")
    }
}

struct SetDurationVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Duration Variable"
    static let description = IntentDescription("Store a duration in seconds under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Seconds") var seconds: Double
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard seconds >= 0 else { throw BywayError.invalidValue("Duration cannot be negative.") }
        _ = try await VariableRepository.shared.set(key: key, value: .duration(seconds), expiresAt: expiresAt)
        return .result(value: seconds, dialog: "Saved \(key).")
    }
}

struct SetMeasurementVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Measurement Variable"
    static let description = IntentDescription("Store a numeric measurement and its unit symbol.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Value") var value: Double
    @Parameter(title: "Unit Symbol") var unitSymbol: String
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard !unitSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BywayError.invalidValue("The unit symbol cannot be empty.")
        }
        let measurement = BywayMeasurement(value: value, unitSymbol: unitSymbol)
        _ = try await VariableRepository.shared.set(key: key, value: .measurement(measurement), expiresAt: expiresAt)
        return .result(value: "\(value) \(unitSymbol)", dialog: "Saved \(key).")
    }
}

struct SetListVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set List Variable"
    static let description = IntentDescription("Store a list of text values under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(
        title: "List",
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var values: [String]
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(
            key: key,
            value: .array(values.map(VariableValue.text)),
            expiresAt: expiresAt
        )
        return .result(value: values, dialog: "Saved \(values.count) items in \(key).")
    }
}

struct SetJSONVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set JSON Variable"
    static let description = IntentDescription("Store a JSON array, dictionary, or primitive value.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(
        title: "JSON",
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var json: String
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let value = try VariableValue.fromJSON(json)
        _ = try await VariableRepository.shared.set(key: key, value: value, expiresAt: expiresAt)
        return .result(value: value.jsonString, dialog: "Saved \(key).")
    }
}

struct SetDateVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Date Variable"
    static let description = IntentDescription("Store a date under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Date") var value: Date
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(key: key, value: .date(value), expiresAt: expiresAt)
        return .result(value: value, dialog: "Saved \(key).")
    }
}

struct SetLocationVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Location Variable"
    static let description = IntentDescription("Store latitude and longitude under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Latitude") var latitude: Double
    @Parameter(title: "Longitude") var longitude: Double
    @Parameter(title: "Name") var name: String?
    @Parameter(title: "Altitude") var altitude: Double?
    @Parameter(title: "Horizontal Accuracy") var horizontalAccuracy: Double?
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw BywayError.invalidValue("The coordinates are outside the valid range.")
        }
        let location = BywayLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            name: name
        )
        _ = try await VariableRepository.shared.set(key: key, value: .location(location), expiresAt: expiresAt)
        return .result(value: "\(latitude),\(longitude)", dialog: "Saved \(key).")
    }
}

struct SetURLVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set URL Variable"
    static let description = IntentDescription("Store a URL under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "URL") var value: URL
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<URL> & ProvidesDialog {
        _ = try await VariableRepository.shared.set(key: key, value: .url(value), expiresAt: expiresAt)
        return .result(value: value, dialog: "Saved \(key).")
    }
}

struct SetFileVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set File Variable"
    static let description = IntentDescription("Copy a file into byway and store it under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(
        title: "File",
        supportedContentTypes: [.data],
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var file: IntentFile
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let sourceURL = file.fileURL else {
            throw BywayError.invalidValue("Shortcuts did not provide a readable file.")
        }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let values = try sourceURL.resourceValues(forKeys: [.contentTypeKey])
        let stored = try await VariableRepository.shared.saveFile(
            data: Data(contentsOf: sourceURL),
            filename: sourceURL.lastPathComponent,
            contentType: values.contentType?.identifier ?? UTType.data.identifier
        )
        _ = try await VariableRepository.shared.set(key: key, value: .file(stored), expiresAt: expiresAt)
        return .result(dialog: "Stored \(stored.filename) in \(key).")
    }
}

struct SetDataVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Data Variable"
    static let description = IntentDescription("Store raw binary data from a file without retaining its filename.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(
        title: "Data",
        supportedContentTypes: [.data],
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var input: IntentFile
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = input.fileURL else {
            throw BywayError.invalidValue("Shortcuts did not provide readable data.")
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        _ = try await VariableRepository.shared.set(
            key: key,
            value: .data(Data(contentsOf: url)),
            expiresAt: expiresAt
        )
        return .result(dialog: "Saved binary data in \(key).")
    }
}

struct SetNullVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Null Variable"
    static let description = IntentDescription("Store an explicit null value under a persistent global key.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Expiration Date") var expiresAt: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await VariableRepository.shared.set(key: key, value: .null, expiresAt: expiresAt)
        return .result(dialog: "Saved null in \(key).")
    }
}
