import AppIntents
import Foundation
import UniformTypeIdentifiers

struct GetVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Variable"
    static let description = IntentDescription("Retrieve any persistent variable as text or JSON.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$key)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let variable = try await VariableRepository.shared.variable(forKey: key)
        let result = IntentSupport.plainText(for: variable.value)
        return .result(value: result, dialog: "Retrieved \(variable.key).")
    }
}

struct GetTextVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Text Variable"
    static let description = IntentDescription("Retrieve a persistent text variable.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let variable = try await IntentSupport.variable(key: key, expected: .text)
        guard case .text(let value) = variable.value else { throw BywayError.invalidValue("Invalid text value.") }
        return .result(value: value)
    }
}

struct GetBooleanVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Boolean Variable"
    static let description = IntentDescription("Retrieve a persistent true or false value.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let variable = try await IntentSupport.variable(key: key, expected: .boolean)
        guard case .boolean(let value) = variable.value else { throw BywayError.invalidValue("Invalid Boolean value.") }
        return .result(value: value)
    }
}

struct GetIntegerVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Integer Variable"
    static let description = IntentDescription("Retrieve a persistent integer.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let variable = try await IntentSupport.variable(key: key, expected: .integer)
        guard case .integer(let value) = variable.value,
              value >= Int64(Int.min), value <= Int64(Int.max) else {
            throw BywayError.invalidValue("The stored integer is outside this device's supported range.")
        }
        return .result(value: Int(value))
    }
}

struct GetNumberVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Number Variable"
    static let description = IntentDescription("Retrieve a persistent integer or decimal number.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let variable = try await VariableRepository.shared.variable(forKey: key)
        switch variable.value {
        case .integer(let value): return .result(value: Double(value))
        case .number(let value): return .result(value: value)
        default:
            throw BywayError.typeMismatch(expected: .number, actual: variable.value.kind)
        }
    }
}

struct GetDurationVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Duration Variable"
    static let description = IntentDescription("Retrieve a duration as seconds.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let variable = try await IntentSupport.variable(key: key, expected: .duration)
        guard case .duration(let seconds) = variable.value else {
            throw BywayError.invalidValue("Invalid duration value.")
        }
        return .result(value: seconds)
    }
}

struct GetMeasurementVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Measurement Variable"
    static let description = IntentDescription("Retrieve a measurement as formatted text.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let variable = try await IntentSupport.variable(key: key, expected: .measurement)
        guard case .measurement(let value) = variable.value else {
            throw BywayError.invalidValue("Invalid measurement value.")
        }
        return .result(value: "\(value.value) \(value.unitSymbol)")
    }
}

struct GetListVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get List Variable"
    static let description = IntentDescription("Retrieve an array as a list of text values.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let variable = try await IntentSupport.variable(key: key, expected: .array)
        guard case .array(let values) = variable.value else {
            throw BywayError.invalidValue("Invalid list value.")
        }
        return .result(value: values.map(IntentSupport.plainText))
    }
}

struct GetJSONVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Variable as JSON"
    static let description = IntentDescription("Retrieve a variable as a JSON string.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let variable = try await VariableRepository.shared.variable(forKey: key)
        return .result(value: variable.value.jsonString)
    }
}

struct GetDateVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Date Variable"
    static let description = IntentDescription("Retrieve a persistent date.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<Date> {
        let variable = try await IntentSupport.variable(key: key, expected: .date)
        guard case .date(let value) = variable.value else { throw BywayError.invalidValue("Invalid date value.") }
        return .result(value: value)
    }
}

struct GetURLVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get URL Variable"
    static let description = IntentDescription("Retrieve a persistent URL.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<URL> {
        let variable = try await IntentSupport.variable(key: key, expected: .url)
        guard case .url(let value) = variable.value else { throw BywayError.invalidValue("Invalid URL value.") }
        return .result(value: value)
    }
}

struct GetFileVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get File Variable"
    static let description = IntentDescription("Retrieve a file stored in byway.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let variable = try await IntentSupport.variable(key: key, expected: .file)
        guard case .file(let file) = variable.value else { throw BywayError.invalidValue("Invalid file value.") }
        let data = try await VariableRepository.shared.fileData(for: file)
        let intentFile = IntentFile(
            data: data,
            filename: file.filename,
            type: UTType(file.contentType) ?? .data
        )
        return .result(value: intentFile, dialog: "Retrieved \(file.filename).")
    }
}

struct GetDataVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Data Variable"
    static let description = IntentDescription("Retrieve stored binary data as a file.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let variable = try await IntentSupport.variable(key: key, expected: .data)
        guard case .data(let data) = variable.value else {
            throw BywayError.invalidValue("Invalid data value.")
        }
        return .result(value: IntentFile(data: data, filename: "\(variable.key).bin", type: .data))
    }
}

struct GetLocationVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Location Variable"
    static let description = IntentDescription("Retrieve a stored location as a Maps URL.")
    static let openAppWhenRun = false

    @Parameter(title: "Key") var key: String

    func perform() async throws -> some IntentResult & ReturnsValue<URL> {
        let variable = try await IntentSupport.variable(key: key, expected: .location)
        guard case .location(let location) = variable.value else {
            throw BywayError.invalidValue("Invalid location value.")
        }
        return .result(value: try IntentSupport.mapsURL(for: location))
    }
}
