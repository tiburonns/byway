import Foundation

struct BywayLocation: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var horizontalAccuracy: Double?
    var name: String?
}

struct StoredFile: Codable, Hashable, Sendable {
    var id: UUID
    var filename: String
    var contentType: String
    var byteCount: Int

    init(id: UUID = UUID(), filename: String, contentType: String, byteCount: Int) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.byteCount = byteCount
    }
}

struct BywayMeasurement: Codable, Hashable, Sendable {
    var value: Double
    var unitSymbol: String
}

indirect enum VariableValue: Codable, Hashable, Sendable {
    case text(String)
    case boolean(Bool)
    case integer(Int64)
    case number(Double)
    case duration(TimeInterval)
    case measurement(BywayMeasurement)
    case array([VariableValue])
    case dictionary([String: VariableValue])
    case date(Date)
    case location(BywayLocation)
    case url(URL)
    case data(Data)
    case file(StoredFile)
    case null

    var kind: VariableKind {
        switch self {
        case .text: .text
        case .boolean: .boolean
        case .integer: .integer
        case .number: .number
        case .duration: .duration
        case .measurement: .measurement
        case .array: .array
        case .dictionary: .dictionary
        case .date: .date
        case .location: .location
        case .url: .url
        case .data: .data
        case .file: .file
        case .null: .null
        }
    }

    var summary: String {
        switch self {
        case .text(let value):
            value.isEmpty ? "Empty text" : value
        case .boolean(let value):
            value ? "True" : "False"
        case .integer(let value):
            value.formatted()
        case .number(let value):
            value.formatted()
        case .duration(let seconds):
            "\(seconds.formatted()) seconds"
        case .measurement(let value):
            "\(value.value.formatted()) \(value.unitSymbol)"
        case .array(let values):
            "\(values.count) item\(values.count == 1 ? "" : "s")"
        case .dictionary(let values):
            "\(values.count) key\(values.count == 1 ? "" : "s")"
        case .date(let value):
            value.formatted(date: .abbreviated, time: .shortened)
        case .location(let value):
            value.name ?? "\(value.latitude.formatted()), \(value.longitude.formatted())"
        case .url(let value):
            value.absoluteString
        case .data(let value):
            ByteCountFormatter.string(fromByteCount: Int64(value.count), countStyle: .file)
        case .file(let value):
            value.filename
        case .null:
            "Null"
        }
    }

    var jsonObject: Any {
        switch self {
        case .text(let value): value
        case .boolean(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .duration(let value): ["seconds": value]
        case .measurement(let value): ["value": value.value, "unit": value.unitSymbol]
        case .array(let values): values.map(\.jsonObject)
        case .dictionary(let values): values.mapValues(\.jsonObject)
        case .date(let value): ISO8601DateFormatter().string(from: value)
        case .location(let value):
            {
                var result: [String: Any] = [
                    "latitude": value.latitude,
                    "longitude": value.longitude
                ]
                if let altitude = value.altitude { result["altitude"] = altitude }
                if let accuracy = value.horizontalAccuracy { result["horizontalAccuracy"] = accuracy }
                if let name = value.name { result["name"] = name }
                return result
            }()
        case .url(let value): value.absoluteString
        case .data(let value): value.base64EncodedString()
        case .file(let value):
            [
                "id": value.id.uuidString,
                "filename": value.filename,
                "contentType": value.contentType,
                "byteCount": value.byteCount
            ]
        case .null: NSNull()
        }
    }

    var jsonString: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return summary
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func fromJSONObject(_ object: Any) throws -> VariableValue {
        switch object {
        case let value as String:
            return .text(value)
        case let value as Bool:
            return .boolean(value)
        case let value as NSNumber:
            let double = value.doubleValue
            if floor(double) == double,
               double >= Double(Int64.min),
               double <= Double(Int64.max) {
                return .integer(value.int64Value)
            }
            return .number(double)
        case let values as [Any]:
            return .array(try values.map(fromJSONObject))
        case let values as [String: Any]:
            return .dictionary(try values.mapValues(fromJSONObject))
        case is NSNull:
            return .null
        default:
            throw BywayError.invalidValue("Unsupported JSON value")
        }
    }

    static func fromJSON(_ text: String) throws -> VariableValue {
        guard let data = text.data(using: .utf8) else {
            throw BywayError.invalidValue("The JSON is not valid UTF-8")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try fromJSONObject(object)
    }
}
