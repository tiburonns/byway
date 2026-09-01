import Foundation

enum AuditError: LocalizedError {
    case failed([String])

    var errorDescription: String? {
        switch self {
        case .failed(let failures):
            return failures.joined(separator: "\n")
        }
    }
}

let requiredIntentParameters: [String: Set<String>] = [
    "AppendEventIntent": ["key", "category", "action"],
    "EnsureVariableIntent": ["key", "json"],
    "GenerateUUIDIntent": [],
    "GetBooleanVariableIntent": ["key"],
    "GetDictionaryEntryIntent": ["key", "path"],
    "GetJSONVariableIntent": ["key"],
    "GetLocationVariableIntent": ["key"],
    "GetTextVariableIntent": ["key"],
    "IncrementVariableIntent": ["key", "amount"],
    "QueryEventsIntent": ["key", "limit", "order"],
    "SetBooleanVariableIntent": ["key", "value"],
    "SetDateVariableIntent": ["key", "value"],
    "SetDictionaryEntryIntent": ["key", "field", "jsonValue"],
    "SetIntegerVariableIntent": ["key", "value"],
    "SetLocationVariableIntent": ["key", "latitude", "longitude"],
    "SetSystemModeIntent": ["mode", "source"],
    "SetTextVariableIntent": ["key", "value"]
]

let allowedAskCounts: [String: Int] = [
    "DB — Registrar evento": 3,
    "DB — Log Event": 3,
    "UI — Guardar selección": 2,
    "UI — Save Selection": 2,
    "UI — Obtener última selección": 1,
    "UI — Get Last Selection": 1,
    "NAV — Iniciar ruta": 1,
    "NAV — Start Route": 1,
    "HOME — Procesar estado": 1,
    "HOME — Process State": 1
]

func containsAskEachTime(_ value: Any) -> Bool {
    if let text = value as? String {
        return text.localizedCaseInsensitiveContains("Ask Each Time")
            || text.localizedCaseInsensitiveContains("Preguntar cada vez")
    }
    if let dictionary = value as? [String: Any] {
        if (dictionary["Type"] as? String) == "Ask" { return true }
        return dictionary.values.contains(where: containsAskEachTime)
    }
    if let array = value as? [Any] {
        return array.contains(where: containsAskEachTime)
    }
    return false
}

func audit(directory: URL) throws {
    let manager = FileManager.default
    let files = try manager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "shortcut" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    var failures: [String] = []
    if files.count != 30 {
        failures.append("\(directory.path): expected 30 shortcuts, found \(files.count)")
    }

    for file in files {
        let name = file.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        let data = try Data(contentsOf: file)
        guard
            let workflow = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let actions = workflow["WFWorkflowActions"] as? [[String: Any]]
        else {
            failures.append("\(name): invalid workflow property list")
            continue
        }

        let importQuestions = workflow["WFWorkflowImportQuestions"] as? [Any] ?? []
        if !importQuestions.isEmpty {
            failures.append("\(name): contains import questions")
        }

        var askCount = 0
        for (index, action) in actions.enumerated() {
            let identifier = action["WFWorkflowActionIdentifier"] as? String ?? ""
            let parameters = action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]

            if containsAskEachTime(parameters) {
                failures.append("\(name), action \(index + 1): contains Ask Each Time")
            }

            switch identifier {
            case "is.workflow.actions.ask":
                askCount += 1
                if (parameters["WFAskActionPrompt"] as? String)?.isEmpty != false {
                    failures.append("\(name), action \(index + 1): empty Ask for Input prompt")
                }
            case "is.workflow.actions.date":
                if parameters["WFDateActionMode"] as? String != "Current Date" {
                    failures.append("\(name), action \(index + 1): ambiguous Date action")
                }
                if parameters["WFDateActionDate"] != nil {
                    failures.append("\(name), action \(index + 1): current date unexpectedly has a specified date")
                }
            case "is.workflow.actions.runworkflow":
                if (parameters["WFWorkflowName"] as? String)?.isEmpty != false {
                    failures.append("\(name), action \(index + 1): missing shortcut name")
                }
            default:
                guard identifier.hasPrefix("com.tiburonns.byway.") else { continue }
                let intent = String(identifier.dropFirst("com.tiburonns.byway.".count))
                guard let required = requiredIntentParameters[intent] else {
                    failures.append("\(name), action \(index + 1): unaudited intent \(intent)")
                    continue
                }
                let missing = required.subtracting(parameters.keys)
                if !missing.isEmpty {
                    failures.append("\(name), action \(index + 1): \(intent) missing \(missing.sorted().joined(separator: ", "))")
                }
            }
        }

        let expectedAsks = allowedAskCounts[name] ?? 0
        if askCount != expectedAsks {
            failures.append("\(name): expected \(expectedAsks) intentional prompts, found \(askCount)")
        }
    }

    if !failures.isEmpty { throw AuditError.failed(failures) }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw AuditError.failed(["Usage: AuditWorkflowShortcuts <spanish-directory> <english-directory>"])
    }
    try audit(directory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    try audit(directory: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
    print("PASS: 30 Spanish and 30 English shortcuts have explicit dates, complete intent inputs, and only intentional prompts")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
    exit(1)
}
