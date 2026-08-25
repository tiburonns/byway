import AppIntents
import Foundation

enum IntentSupport {
    static func variable(key: String, expected: VariableKind) async throws -> GlobalVariable {
        let variable = try await VariableRepository.shared.variable(forKey: key)
        guard variable.value.kind == expected else {
            throw BywayError.typeMismatch(expected: expected, actual: variable.value.kind)
        }
        return variable
    }

    static func plainText(for value: VariableValue) -> String {
        switch value {
        case .text(let value): value
        case .boolean(let value): value ? "true" : "false"
        case .integer(let value): String(value)
        case .number(let value): String(value)
        case .duration(let value): String(value)
        case .measurement(let value): "\(value.value) \(value.unitSymbol)"
        case .date(let value): ISO8601DateFormatter().string(from: value)
        case .url(let value): value.absoluteString
        case .location(let value):
            value.name.map { "\($0): \(value.latitude), \(value.longitude)" }
                ?? "\(value.latitude), \(value.longitude)"
        case .array, .dictionary: value.jsonString
        case .data(let value): value.base64EncodedString()
        case .file(let value): value.filename
        case .null: "null"
        }
    }
}
