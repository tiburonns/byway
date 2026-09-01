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

    static func data(for file: IntentFile) throws -> Data {
        guard let url = file.fileURL else { return file.data }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    static func mapsURL(for location: BywayLocation) throws -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")
        var queryItems = [URLQueryItem(
            name: "ll",
            value: "\(location.latitude),\(location.longitude)"
        )]
        if let name = location.name, !name.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: name))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw BywayError.invalidValue("Could not create a Maps URL for this location.")
        }
        return url
    }

    static func batchMutations(from json: String, expiresAt: Date?) throws -> [VariableMutation] {
        let object = try jsonObject(from: json)
        guard let dictionary = object as? [String: Any], !dictionary.isEmpty else {
            throw BywayError.invalidValue("Batch Set requires a non-empty JSON object keyed by variable name.")
        }
        return try dictionary.keys.sorted().map { key in
            .set(key: key, value: try VariableValue.fromTypedJSONObject(dictionary[key]!), expiresAt: expiresAt)
        }
    }

    static func transactionMutations(from json: String) throws -> [VariableMutation] {
        let object = try jsonObject(from: json)
        guard let operations = object as? [Any], !operations.isEmpty else {
            throw BywayError.invalidValue("A transaction requires a non-empty JSON array of operations.")
        }
        return try operations.enumerated().map { index, item in
            guard let operation = item as? [String: Any],
                  let name = operation["operation"] as? String,
                  let key = operation["key"] as? String else {
                throw BywayError.invalidValue("Transaction operation \(index) requires 'operation' and 'key'.")
            }
            let expiration = try optionalDate(operation["expiresAt"], field: "expiresAt")
            switch name.lowercased() {
            case "set":
                guard let object = operation["value"] else {
                    throw BywayError.invalidValue("Set operation \(index) requires 'value'.")
                }
                return .set(key: key, value: try VariableValue.fromTypedJSONObject(object), expiresAt: expiration)
            case "ensure", "initialize":
                guard let object = operation["value"] else {
                    throw BywayError.invalidValue("Ensure operation \(index) requires 'value'.")
                }
                return .ensure(key: key, value: try VariableValue.fromTypedJSONObject(object), expiresAt: expiration)
            case "delete":
                return .delete(key: key)
            case "append":
                if let values = operation["values"] as? [Any] {
                    return .append(key: key, values: try values.map(VariableValue.fromTypedJSONObject))
                }
                guard let value = operation["value"] else {
                    throw BywayError.invalidValue("Append operation \(index) requires 'value' or 'values'.")
                }
                return .append(key: key, values: [try VariableValue.fromTypedJSONObject(value)])
            case "setdictionary", "setdictionaryentry":
                guard let path = (operation["path"] ?? operation["field"]) as? String,
                      let value = operation["value"] else {
                    throw BywayError.invalidValue("Set Dictionary operation \(index) requires 'path' and 'value'.")
                }
                return .setDictionaryEntry(
                    key: key,
                    path: path,
                    value: try VariableValue.fromTypedJSONObject(value)
                )
            case "removedictionary", "removedictionaryentry":
                guard let path = (operation["path"] ?? operation["field"]) as? String else {
                    throw BywayError.invalidValue("Remove Dictionary operation \(index) requires 'path'.")
                }
                return .removeDictionaryEntry(key: key, path: path)
            default:
                throw BywayError.invalidValue("Unsupported transaction operation '\(name)'.")
            }
        }
    }

    static func jsonValue(from json: String) throws -> VariableValue {
        try VariableValue.fromTypedJSONObject(jsonObject(from: json))
    }

    private static func jsonObject(from text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw BywayError.invalidValue("The JSON is not valid UTF-8.")
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func optionalDate(_ object: Any?, field: String) throws -> Date? {
        guard let object else { return nil }
        guard let text = object as? String, let date = ISO8601DateFormatter().date(from: text) else {
            throw BywayError.invalidValue("'\(field)' must be an ISO 8601 date string.")
        }
        return date
    }
}
