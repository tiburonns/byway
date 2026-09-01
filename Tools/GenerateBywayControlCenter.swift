import Foundation

struct ActionMetadata {
    let identifier: String
    let title: String
}

struct Category {
    let title: String
    var actions: [ActionMetadata]
}

enum GeneratorError: LocalizedError {
    case usage
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: GenerateBywayControlCenter <extract.actionsdata> <output.shortcut>"
        case .invalidMetadata:
            "The App Intents metadata does not contain a valid actions dictionary."
        }
    }
}

func uuid() -> String {
    UUID().uuidString.uppercased()
}

func categoryTitle(for action: ActionMetadata) -> String {
    let title = action.title
    if title.localizedCaseInsensitiveContains("Folder") {
        return "Carpetas"
    }
    if title.localizedCaseInsensitiveContains("Event") || action.identifier == "GenerateUUIDIntent" {
        return "Eventos e historial"
    }
    if title.hasPrefix("Import") || title.hasPrefix("Export") {
        return "Importar y exportar"
    }
    if title.localizedCaseInsensitiveContains("List Item")
        || title.localizedCaseInsensitiveContains("List Items")
        || title.localizedCaseInsensitiveContains("Dictionary Entry")
        || action.identifier == "AppendJSONToListIntent"
        || action.identifier == "AppendToListVariableIntent"
        || action.identifier == "SortListIntent" {
        return "Listas y diccionarios"
    }
    if title.hasPrefix("Get") || title.hasPrefix("List Variable") || title.hasSuffix("Exists") {
        return "Consultar variables"
    }
    if title.hasPrefix("Set") || action.identifier == "BatchSetVariablesIntent" || action.identifier == "EnsureVariableIntent" {
        return "Guardar variables"
    }
    return "Operaciones"
}

func controlAction(
    groupingIdentifier: String,
    mode: Int,
    menuItems: [String]? = nil,
    menuItemTitle: String? = nil,
    prompt: String? = nil
) -> [String: Any] {
    var parameters: [String: Any] = [
        "GroupingIdentifier": groupingIdentifier,
        "WFControlFlowMode": mode,
        "UUID": uuid()
    ]
    if let menuItems { parameters["WFMenuItems"] = menuItems }
    if let menuItemTitle { parameters["WFMenuItemTitle"] = menuItemTitle }
    if let prompt { parameters["WFMenuPrompt"] = prompt }
    return [
        "WFWorkflowActionIdentifier": "is.workflow.actions.choosefrommenu",
        "WFWorkflowActionParameters": parameters
    ]
}

func appIntentAction(_ action: ActionMetadata) -> [String: Any] {
    [
        "WFWorkflowActionIdentifier": "com.tiburonns.byway.\(action.identifier)",
        "WFWorkflowActionParameters": [
            "AppIntentDescriptor": [
                "AppIntentIdentifier": action.identifier,
                "BundleIdentifier": "com.tiburonns.byway",
                "Name": "byway",
                "TeamIdentifier": "BPBM5SVGCF"
            ],
            "UUID": uuid()
        ]
    ]
}

func buildWorkflow(actions allActions: [ActionMetadata]) -> [String: Any] {
    let categoryOrder = [
        "Guardar variables",
        "Consultar variables",
        "Operaciones",
        "Listas y diccionarios",
        "Eventos e historial",
        "Carpetas",
        "Importar y exportar"
    ]
    let grouped = Dictionary(grouping: allActions, by: categoryTitle)
    let categories = categoryOrder.compactMap { title -> Category? in
        guard let actions = grouped[title], !actions.isEmpty else { return nil }
        return Category(title: title, actions: actions.sorted { $0.title < $1.title })
    }

    var workflowActions: [[String: Any]] = [[
        "WFWorkflowActionIdentifier": "is.workflow.actions.comment",
        "WFWorkflowActionParameters": [
            "WFCommentActionText": "Centro de control de byway. Elige una categoría y después una acción. Atajos solicitará los parámetros necesarios."
        ]
    ]]

    let rootGroup = uuid()
    workflowActions.append(controlAction(
        groupingIdentifier: rootGroup,
        mode: 0,
        menuItems: categories.map(\.title),
        prompt: "¿Qué quieres hacer con byway?"
    ))

    for category in categories {
        workflowActions.append(controlAction(
            groupingIdentifier: rootGroup,
            mode: 1,
            menuItemTitle: category.title
        ))

        let categoryGroup = uuid()
        workflowActions.append(controlAction(
            groupingIdentifier: categoryGroup,
            mode: 0,
            menuItems: category.actions.map(\.title),
            prompt: category.title
        ))
        for action in category.actions {
            workflowActions.append(controlAction(
                groupingIdentifier: categoryGroup,
                mode: 1,
                menuItemTitle: action.title
            ))
            workflowActions.append(appIntentAction(action))
        }
        workflowActions.append(controlAction(groupingIdentifier: categoryGroup, mode: 2))
    }
    workflowActions.append(controlAction(groupingIdentifier: rootGroup, mode: 2))

    return [
        "WFWorkflowActions": workflowActions,
        "WFWorkflowClientRelease": "4.0",
        "WFWorkflowClientVersion": "4044.0.3",
        "WFWorkflowIcon": [
            "WFWorkflowIconGlyphNumber": 59511,
            "WFWorkflowIconStartColor": 4282601983
        ],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": []
    ]
}

do {
    guard CommandLine.arguments.count == 3 else { throw GeneratorError.usage }
    let metadataURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL))
    guard let root = object as? [String: Any],
          let rawActions = root["actions"] as? [String: [String: Any]] else {
        throw GeneratorError.invalidMetadata
    }

    let actions = try rawActions.map { identifier, metadata -> ActionMetadata in
        guard let titleContainer = metadata["title"] as? [String: Any],
              let title = titleContainer["key"] as? String else {
            throw GeneratorError.invalidMetadata
        }
        return ActionMetadata(identifier: identifier, title: title)
    }
    guard actions.count == 64 else {
        throw NSError(domain: "BywayShortcutGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Expected 64 actions, found \(actions.count)."
        ])
    }

    let workflow = buildWorkflow(actions: actions)
    let data = try PropertyListSerialization.data(fromPropertyList: workflow, format: .xml, options: 0)
    try data.write(to: outputURL, options: .atomic)
    print("Generated \(actions.count) byway actions at \(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
