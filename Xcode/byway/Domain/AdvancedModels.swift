import Foundation

struct BywayEvent: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var category: String
    var action: String
    var timestamp: Date
    var details: [String: VariableValue]

    init(
        id: UUID = UUID(),
        category: String,
        action: String,
        timestamp: Date = .now,
        details: [String: VariableValue] = [:]
    ) {
        self.id = id
        self.category = category
        self.action = action
        self.timestamp = timestamp
        self.details = details
    }

    var variableValue: VariableValue {
        .dictionary([
            "id": .text(id.uuidString),
            "category": .text(category),
            "action": .text(action),
            "timestamp": .date(timestamp),
            "details": .dictionary(details)
        ])
    }

    init(variableValue: VariableValue) throws {
        guard case .dictionary(let dictionary) = variableValue else {
            throw BywayError.invalidValue("The event is not a dictionary.")
        }
        guard case .text(let idText)? = dictionary["id"], let id = UUID(uuidString: idText) else {
            throw BywayError.invalidValue("The event has no valid UUID.")
        }
        guard case .text(let category)? = dictionary["category"], !category.isEmpty else {
            throw BywayError.invalidValue("The event has no category.")
        }
        guard case .text(let action)? = dictionary["action"], !action.isEmpty else {
            throw BywayError.invalidValue("The event has no action.")
        }

        let timestamp: Date
        switch dictionary["timestamp"] ?? dictionary["date"] {
        case .date(let value):
            timestamp = value
        case .text(let value):
            guard let parsed = ISO8601DateFormatter().date(from: value) else {
                throw BywayError.invalidValue("The event has no valid timestamp.")
            }
            timestamp = parsed
        default:
            throw BywayError.invalidValue("The event has no valid timestamp.")
        }

        let details: [String: VariableValue]
        if case .dictionary(let value)? = dictionary["details"] {
            details = value
        } else {
            details = dictionary.filter { !["id", "category", "action", "timestamp", "date"].contains($0.key) }
        }

        self.init(id: id, category: category, action: action, timestamp: timestamp, details: details)
    }
}

enum VariableMutation: Sendable {
    case set(key: String, value: VariableValue, expiresAt: Date?)
    case ensure(key: String, value: VariableValue, expiresAt: Date?)
    case replace(GlobalVariable)
    case delete(key: String)
    case append(key: String, values: [VariableValue])
    case setDictionaryEntry(key: String, path: String, value: VariableValue)
    case removeDictionaryEntry(key: String, path: String)
    case move(key: String, folderID: UUID?)

    var key: String {
        switch self {
        case .set(let key, _, _), .ensure(let key, _, _), .delete(let key),
             .append(let key, _), .setDictionaryEntry(let key, _, _),
             .removeDictionaryEntry(let key, _), .move(let key, _):
            key
        case .replace(let variable):
            variable.key
        }
    }
}

struct TransactionSummary: Sendable {
    var affectedKeys: [String]
    var createdCount: Int
    var updatedCount: Int
    var deletedCount: Int
    var skippedCount: Int
}

extension VariableValue {
    func value(atPath path: String) throws -> VariableValue? {
        let components = try Self.pathComponents(path)
        return value(atPath: components[...])
    }

    func settingValue(_ newValue: VariableValue, atPath path: String) throws -> VariableValue {
        let components = try Self.pathComponents(path)
        return try settingValue(newValue, atPath: components[...])
    }

    func removingValue(atPath path: String) throws -> (value: VariableValue, removed: VariableValue?) {
        let components = try Self.pathComponents(path)
        return try removingValue(atPath: components[...])
    }

    static func fromTypedJSONObject(_ object: Any) throws -> VariableValue {
        guard let envelope = object as? [String: Any], let type = envelope["$type"] as? String else {
            return try fromJSONObject(object)
        }

        switch type.lowercased() {
        case "text", "string":
            guard let value = envelope["value"] as? String else {
                throw BywayError.invalidValue("A text value requires a string in 'value'.")
            }
            return .text(value)
        case "boolean", "bool":
            guard let value = envelope["value"] as? Bool else {
                throw BywayError.invalidValue("A Boolean value requires true or false in 'value'.")
            }
            return .boolean(value)
        case "integer", "int":
            guard let number = envelope["value"] as? NSNumber else {
                throw BywayError.invalidValue("An integer value requires a number in 'value'.")
            }
            let decimal = Decimal(string: number.stringValue)
            guard let decimal, decimal.rounded() == decimal,
                  decimal >= Decimal(Int64.min), decimal <= Decimal(Int64.max) else {
                throw BywayError.invalidValue("The integer is outside the supported 64-bit range.")
            }
            return .integer(NSDecimalNumber(decimal: decimal).int64Value)
        case "number", "decimal":
            guard let value = envelope["value"] as? NSNumber else {
                throw BywayError.invalidValue("A number requires a numeric 'value'.")
            }
            return .number(value.doubleValue)
        case "duration":
            guard let value = envelope["seconds"] as? NSNumber ?? envelope["value"] as? NSNumber else {
                throw BywayError.invalidValue("A duration requires 'seconds'.")
            }
            guard value.doubleValue >= 0, value.doubleValue.isFinite else {
                throw BywayError.invalidValue("A duration must be a non-negative finite number.")
            }
            return .duration(value.doubleValue)
        case "measurement":
            guard let value = envelope["value"] as? NSNumber,
                  let unit = envelope["unit"] as? String, !unit.isEmpty else {
                throw BywayError.invalidValue("A measurement requires numeric 'value' and string 'unit'.")
            }
            return .measurement(BywayMeasurement(value: value.doubleValue, unitSymbol: unit))
        case "date":
            guard let value = envelope["value"] as? String,
                  let date = ISO8601DateFormatter().date(from: value) else {
                throw BywayError.invalidValue("A date requires an ISO 8601 string in 'value'.")
            }
            return .date(date)
        case "location":
            guard let latitude = envelope["latitude"] as? NSNumber,
                  let longitude = envelope["longitude"] as? NSNumber else {
                throw BywayError.invalidValue("A location requires latitude and longitude.")
            }
            guard (-90...90).contains(latitude.doubleValue),
                  (-180...180).contains(longitude.doubleValue) else {
                throw BywayError.invalidValue("The coordinates are outside the valid range.")
            }
            return .location(BywayLocation(
                latitude: latitude.doubleValue,
                longitude: longitude.doubleValue,
                altitude: (envelope["altitude"] as? NSNumber)?.doubleValue,
                horizontalAccuracy: (envelope["accuracy"] as? NSNumber)?.doubleValue
                    ?? (envelope["horizontalAccuracy"] as? NSNumber)?.doubleValue,
                name: envelope["name"] as? String
            ))
        case "url":
            guard let value = envelope["value"] as? String, let url = URL(string: value) else {
                throw BywayError.invalidValue("A URL requires a valid string in 'value'.")
            }
            return .url(url)
        case "data":
            guard let value = envelope["value"] as? String, let data = Data(base64Encoded: value) else {
                throw BywayError.invalidValue("Data requires Base64 in 'value'.")
            }
            return .data(data)
        case "array", "list":
            guard let values = envelope["value"] as? [Any] else {
                throw BywayError.invalidValue("A list requires an array in 'value'.")
            }
            return .array(try values.map(fromTypedJSONObject))
        case "dictionary", "json":
            guard let values = envelope["value"] as? [String: Any] else {
                throw BywayError.invalidValue("A dictionary requires an object in 'value'.")
            }
            return .dictionary(try values.mapValues(fromTypedJSONObject))
        case "null":
            return .null
        default:
            throw BywayError.invalidValue("Unsupported typed JSON value '\(type)'.")
        }
    }

    private static func pathComponents(_ path: String) throws -> [Substring] {
        let components = path
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
            throw BywayError.invalidValue("A dictionary path cannot be empty or contain empty components.")
        }
        return components.map { Substring($0) }
    }

    private func value(atPath path: ArraySlice<Substring>) -> VariableValue? {
        guard let first = path.first, case .dictionary(let dictionary) = self,
              let child = dictionary[String(first)] else { return nil }
        return path.count == 1 ? child : child.value(atPath: path.dropFirst())
    }

    private func settingValue(_ newValue: VariableValue, atPath path: ArraySlice<Substring>) throws -> VariableValue {
        guard let first = path.first else { return newValue }
        guard case .dictionary(var dictionary) = self else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: kind)
        }
        let key = String(first)
        if path.count == 1 {
            dictionary[key] = newValue
        } else {
            let child = dictionary[key] ?? .dictionary([:])
            dictionary[key] = try child.settingValue(newValue, atPath: path.dropFirst())
        }
        return .dictionary(dictionary)
    }

    private func removingValue(atPath path: ArraySlice<Substring>) throws -> (VariableValue, VariableValue?) {
        guard let first = path.first else { return (self, nil) }
        guard case .dictionary(var dictionary) = self else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: kind)
        }
        let key = String(first)
        if path.count == 1 {
            let removed = dictionary.removeValue(forKey: key)
            return (.dictionary(dictionary), removed)
        }
        guard let child = dictionary[key] else { return (.dictionary(dictionary), nil) }
        let result = try child.removingValue(atPath: path.dropFirst())
        dictionary[key] = result.0
        return (.dictionary(dictionary), result.1)
    }
}

private extension Decimal {
    func rounded() -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return result
    }
}
