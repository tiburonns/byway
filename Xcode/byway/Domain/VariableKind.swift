import Foundation

enum VariableKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case boolean
    case integer
    case number
    case duration
    case measurement
    case array
    case dictionary
    case date
    case location
    case url
    case data
    case file
    case null

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .boolean: "Boolean"
        case .integer: "Integer"
        case .number: "Number"
        case .duration: "Duration"
        case .measurement: "Measurement"
        case .array: "Array"
        case .dictionary: "Dictionary"
        case .date: "Date"
        case .location: "Location"
        case .url: "URL"
        case .data: "Data"
        case .file: "File"
        case .null: "Null"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .boolean: "switch.2"
        case .integer: "number"
        case .number: "function"
        case .duration: "timer"
        case .measurement: "ruler"
        case .array: "list.bullet"
        case .dictionary: "curlybraces"
        case .date: "calendar"
        case .location: "location"
        case .url: "link"
        case .data: "shippingbox"
        case .file: "doc"
        case .null: "nosign"
        }
    }
}
