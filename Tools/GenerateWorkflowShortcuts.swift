import Foundation

typealias Action = [String: Any]

let bywayBundleID = "com.tiburonns.byway"
let bywayTeamID = "BPBM5SVGCF"

func uuid() -> String { UUID().uuidString.uppercased() }

func textToken(_ string: String, attachments: [String: Any] = [:]) -> [String: Any] {
    [
        "Value": ["string": string, "attachmentsByRange": attachments],
        "WFSerializationType": "WFTextTokenString"
    ]
}

func outputValue(_ actionUUID: String, _ name: String, aggrandizements: [[String: Any]] = []) -> [String: Any] {
    var value: [String: Any] = [
        "OutputUUID": actionUUID,
        "Type": "ActionOutput",
        "OutputName": name
    ]
    if !aggrandizements.isEmpty { value["Aggrandizements"] = aggrandizements }
    return value
}

func outputAttachment(_ actionUUID: String, _ name: String, aggrandizements: [[String: Any]] = []) -> [String: Any] {
    [
        "Value": outputValue(actionUUID, name, aggrandizements: aggrandizements),
        "WFSerializationType": "WFTextTokenAttachment"
    ]
}

func outputText(_ actionUUID: String, _ name: String, prefix: String = "", suffix: String = "", aggrandizements: [[String: Any]] = []) -> [String: Any] {
    let placeholder = "\u{FFFC}"
    return textToken(prefix + placeholder + suffix, attachments: [
        "{\(prefix.utf16.count), 1}": outputValue(actionUUID, name, aggrandizements: aggrandizements)
    ])
}

func systemAction(_ identifier: String, _ parameters: [String: Any] = [:], actionUUID: String? = nil) -> Action {
    var values = parameters
    values["UUID"] = actionUUID ?? uuid()
    return [
        "WFWorkflowActionIdentifier": identifier,
        "WFWorkflowActionParameters": values
    ]
}

func appIntent(_ identifier: String, _ parameters: [String: Any] = [:], actionUUID: String? = nil) -> Action {
    var values = parameters
    values["AppIntentDescriptor"] = [
        "AppIntentIdentifier": identifier,
        "BundleIdentifier": bywayBundleID,
        "Name": "byway",
        "TeamIdentifier": bywayTeamID
    ]
    values["UUID"] = actionUUID ?? uuid()
    return [
        "WFWorkflowActionIdentifier": "\(bywayBundleID).\(identifier)",
        "WFWorkflowActionParameters": values
    ]
}

func runShortcut(_ name: String, actionUUID: String? = nil) -> Action {
    systemAction("is.workflow.actions.runworkflow", [
        "WFWorkflow": ["workflowName": name, "isSelf": false],
        "WFWorkflowName": name,
        "WFShowWorkflow": false
    ], actionUUID: actionUUID)
}

func comment(_ value: String) -> Action {
    systemAction("is.workflow.actions.comment", ["WFCommentActionText": value])
}

func show(_ value: Any) -> Action {
    systemAction("is.workflow.actions.showresult", ["Text": value])
}

func notify(_ body: String, title: String = "Byway") -> Action {
    systemAction("is.workflow.actions.notification", [
        "WFNotificationActionTitle": title,
        "WFNotificationActionBody": body,
        "WFNotificationActionSound": false
    ])
}

func ask(_ prompt: String, actionUUID: String) -> Action {
    systemAction("is.workflow.actions.ask", ["WFAskActionPrompt": prompt], actionUUID: actionUUID)
}

func currentDate(_ actionUUID: String) -> Action {
    systemAction("is.workflow.actions.date", actionUUID: actionUUID)
}

func chooseMenu(prompt: String, items: [(String, [Action])]) -> [Action] {
    let group = uuid()
    var result: [Action] = [systemAction("is.workflow.actions.choosefrommenu", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 0,
        "WFMenuItems": items.map(\.0),
        "WFMenuPrompt": prompt
    ])]
    for item in items {
        result.append(systemAction("is.workflow.actions.choosefrommenu", [
            "GroupingIdentifier": group,
            "WFControlFlowMode": 1,
            "WFMenuItemTitle": item.0
        ]))
        result.append(contentsOf: item.1)
    }
    result.append(systemAction("is.workflow.actions.choosefrommenu", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 2
    ]))
    return result
}

func ifEquals(outputUUID: String, outputName: String, value: String, actions: [Action]) -> [Action] {
    let group = uuid()
    var result: [Action] = [systemAction("is.workflow.actions.conditional", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 0,
        "WFCondition": 4,
        "WFConditionalActionString": value,
        "WFInput": [
            "Type": "Variable",
            "Variable": outputAttachment(outputUUID, outputName)
        ]
    ])]
    result.append(contentsOf: actions)
    result.append(systemAction("is.workflow.actions.conditional", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 2
    ]))
    return result
}

func ifBoolean(outputUUID: String, outputName: String, isTrue: Bool, then trueActions: [Action], else falseActions: [Action]) -> [Action] {
    let group = uuid()
    var result: [Action] = [systemAction("is.workflow.actions.conditional", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 0,
        "WFCondition": isTrue ? 4 : 5,
        "WFConditionalActionString": isTrue ? "1" : "0",
        "WFInput": [
            "Type": "Variable",
            "Variable": outputAttachment(outputUUID, outputName)
        ]
    ])]
    result.append(contentsOf: trueActions)
    result.append(systemAction("is.workflow.actions.conditional", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 1
    ]))
    result.append(contentsOf: falseActions)
    result.append(systemAction("is.workflow.actions.conditional", [
        "GroupingIdentifier": group,
        "WFControlFlowMode": 2
    ]))
    return result
}

func bywayString(_ value: String) -> [String: Any] { textToken(value) }

func setText(_ key: String, _ value: Any, actionUUID: String? = nil) -> Action {
    appIntent("SetTextVariableIntent", ["key": bywayString(key), "value": value], actionUUID: actionUUID)
}

func setBool(_ key: String, _ value: Bool) -> Action {
    appIntent("SetBooleanVariableIntent", ["key": bywayString(key), "value": value])
}

func setInteger(_ key: String, _ value: Int) -> Action {
    appIntent("SetIntegerVariableIntent", ["key": bywayString(key), "value": value])
}

func setDate(_ key: String, from actionUUID: String) -> Action {
    appIntent("SetDateVariableIntent", [
        "key": bywayString(key),
        "value": outputAttachment(actionUUID, "Date")
    ])
}

func appendEvent(category: Any, action: Any, details: Any? = nil) -> Action {
    var parameters: [String: Any] = [
        "key": bywayString("HISTORY.Events"),
        "category": category,
        "action": action
    ]
    if let details { parameters["detailsJSON"] = details }
    return appIntent("AppendEventIntent", parameters)
}

func setSelection(mode: String, action: String) -> Action {
    appIntent("SetDictionaryEntryIntent", [
        "key": bywayString("UI.LastSelection"),
        "field": bywayString("\(mode).Manual"),
        "jsonValue": bywayString("\"\(action)\"")
    ])
}

func getLastSelection(mode: String) -> [Action] {
    let getID = uuid()
    return [
        appIntent("GetDictionaryEntryIntent", [
            "key": bywayString("UI.LastSelection"),
            "path": bywayString("\(mode).Manual")
        ], actionUUID: getID),
        show(outputText(getID, "Get Dictionary Entry", prefix: "Última selección de \(mode): "))
    ]
}

func menuShortcut(mode: String, rows: [(String, String, [Action])]) -> [Action] {
    chooseMenu(prompt: "\(mode.uppercased()) · ¿Qué quieres hacer?", items: rows.map { row in
        let (title, code, actions) = row
        return (title, [setSelection(mode: mode, action: code)] + actions)
    })
}

func workflow(_ actions: [Action], color: UInt32 = 4282601983, glyph: Int = 59511) -> [String: Any] {
    [
        "WFWorkflowActions": actions,
        "WFWorkflowClientRelease": "4.0",
        "WFWorkflowClientVersion": "4044.0.3",
        "WFWorkflowIcon": [
            "WFWorkflowIconGlyphNumber": glyph,
            "WFWorkflowIconStartColor": color
        ],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": []
    ]
}

func initializerActions() -> [Action] {
    let generatedAt = ISO8601DateFormatter().string(from: Date())
    let defaults: [(String, String)] = [
        ("SYS.SchemaVersion", "3"),
        ("SYS.Initialized", "false"),
        ("SYS.Mode", "\"Normal\""),
        ("SYS.ModeChangedAt", "{\"$type\":\"date\",\"value\":\"\(generatedAt)\"}"),
        ("SYS.LastAction", "null"),
        ("SYS.LastActionAt", "null"),
        ("SYS.LastSource", "null"),
        ("SYS.Settings", "{\"historyEnabled\":true,\"rememberMenuSelection\":true,\"autoSaveParking\":true,\"navigationResume\":true,\"autoAddShazam\":true,\"homeLoggingEnabled\":true,\"notificationsEnabled\":true}"),
        ("UI.LastSelection", "{}"),
        ("NAV.Active", "false"),
        ("NAV.SessionID", "null"),
        ("NAV.Destination", "null"),
        ("NAV.Name", "null"),
        ("NAV.Transport", "\"Driving\""),
        ("NAV.Provider", "\"AppleMaps\""),
        ("NAV.StartedAt", "null"),
        ("NAV.LastUpdatedAt", "null"),
        ("NAV.ResumeCount", "0"),
        ("CAR.ParkedValid", "false"),
        ("CAR.ParkingID", "null"),
        ("CAR.ParkedLocation", "null"),
        ("CAR.ParkedAt", "null"),
        ("CAR.ParkedAddress", "null"),
        ("CAR.ParkedSource", "null"),
        ("MUSIC.HasLast", "false"),
        ("MUSIC.LastID", "null"),
        ("MUSIC.LastTitle", "null"),
        ("MUSIC.LastArtist", "null"),
        ("MUSIC.LastAlbum", "null"),
        ("MUSIC.LastURL", "null"),
        ("MUSIC.LastShazamAt", "null"),
        ("MUSIC.LastAddedToLibrary", "false"),
        ("HOME.Initialized", "false"),
        ("HOME.State", "{}"),
        ("HOME.LastSyncAt", "null"),
        ("HISTORY.Events", "[]")
    ]
    var actions: [Action] = [comment("Inicializa el esquema 3 de Byway sin sobrescribir valores existentes.")]
    actions += defaults.map { key, json in
        appIntent("EnsureVariableIntent", ["key": bywayString(key), "json": bywayString(json)])
    }
    actions += [
        setBool("SYS.Initialized", true),
        notify("Esquema 3 listo: 36 variables verificadas.", title: "Byway inicializado")
    ]
    return actions
}

func modeActions(_ mode: String, source: String = "SIRI") -> [Action] {
    return [
        comment("Activa el modo \(mode) y registra el cambio."),
        appIntent("SetSystemModeIntent", [
            "mode": bywayString(mode),
            "source": bywayString(source)
        ]),
        notify("Modo \(mode) activado.", title: "Byway")
    ]
}

func buildShortcuts() -> [(String, [Action])] {
    var shortcuts: [(String, [Action])] = []
    shortcuts.append(("BYWAY — Inicializar sistema", initializerActions()))

    let categoryID = uuid(), actionID = uuid(), sourceID = uuid(), detailsID = uuid()
    shortcuts.append(("DB — Registrar evento", [
        ask("Categoría del evento (SYS, UI, CAR, NAV, MUSIC o HOME)", actionUUID: categoryID),
        ask("Acción del evento", actionUUID: actionID),
        ask("Origen (SIRI, ACTION_BUTTON, MENU, CARPLAY, AUTOMATION, HOME o MANUAL)", actionUUID: sourceID),
        systemAction("is.workflow.actions.gettext", [
            "WFTextActionText": textToken("{\"source\":\"\u{FFFC}\"}", attachments: [
                "{11, 1}": outputValue(sourceID, "Provided Input")
            ])
        ], actionUUID: detailsID),
        appendEvent(
            category: outputText(categoryID, "Provided Input"),
            action: outputText(actionID, "Provided Input"),
            details: outputText(detailsID, "Text")
        ),
        notify("Evento guardado.")
    ]))

    shortcuts.append(("SYS — Establecer modo", chooseMenu(prompt: "Selecciona el modo", items: [
        ("⚪ Normal", [runShortcut("Modo Normal")]),
        ("🏠 Casa", [runShortcut("Modo Casa")]),
        ("🚗 Auto", [runShortcut("Modo Auto")]),
        ("💼 Trabajo", [runShortcut("Modo Trabajo")]),
        ("🌙 Noche", [runShortcut("Modo Noche")])
    ])))
    shortcuts.append(("SYS — Cambiar modo", [runShortcut("SYS — Establecer modo")]))

    let getModeID = uuid()
    shortcuts.append(("SYS — Qué modo tengo", [
        appIntent("GetTextVariableIntent", ["key": bywayString("SYS.Mode")], actionUUID: getModeID),
        show(outputText(getModeID, "Get Text Variable", prefix: "Estás en modo ", suffix: "."))
    ]))

    let pathID = uuid(), jsonID = uuid()
    shortcuts.append(("UI — Guardar selección", [
        ask("Clave de selección, por ejemplo Auto.Portrait", actionUUID: pathID),
        ask("Valor JSON, por ejemplo \"NAV_RESUME\"", actionUUID: jsonID),
        appIntent("SetDictionaryEntryIntent", [
            "key": bywayString("UI.LastSelection"),
            "field": outputText(pathID, "Provided Input"),
            "jsonValue": outputText(jsonID, "Provided Input")
        ]),
        notify("Selección guardada.")
    ]))

    let readPathID = uuid(), getSelectionID = uuid()
    shortcuts.append(("UI — Obtener última selección", [
        ask("Clave de selección, por ejemplo Auto.Portrait", actionUUID: readPathID),
        appIntent("GetDictionaryEntryIntent", [
            "key": bywayString("UI.LastSelection"),
            "path": outputText(readPathID, "Provided Input")
        ], actionUUID: getSelectionID),
        show(outputText(getSelectionID, "Get Dictionary Entry"))
    ]))

    let dispatchID = uuid()
    var dispatcher: [Action] = [appIntent("GetTextVariableIntent", ["key": bywayString("SYS.Mode")], actionUUID: dispatchID)]
    for mode in ["Normal", "Casa", "Auto", "Trabajo", "Noche"] {
        dispatcher += ifEquals(outputUUID: dispatchID, outputName: "Get Text Variable", value: mode, actions: [runShortcut("MENU — \(mode)")])
    }
    shortcuts.append(("AB — Principal", dispatcher))

    shortcuts.append(("MENU — Normal", menuShortcut(mode: "Normal", rows: [
        ("↩️ Ver última selección", "LAST", getLastSelection(mode: "Normal")),
        ("⚙️ Ajustes rápidos", "QUICK_SETTINGS", [runShortcut("Ajustes Rápido")]),
        ("🎵 Shazam+", "SHAZAM", [runShortcut("MUSIC — Shazam+")]),
        ("📜 Historial", "HISTORY", [runShortcut("HISTORY — Ver historial")]),
        ("🔄 Cambiar modo", "MODE_CHANGE", [runShortcut("SYS — Cambiar modo")])
    ])))

    shortcuts.append(("MENU — Auto", menuShortcut(mode: "Auto", rows: [
        ("↩️ Ver última selección", "LAST", getLastSelection(mode: "Auto")),
        ("▶️ Reanudar ruta", "NAV_RESUME", [runShortcut("NAV — Reanudar ruta")]),
        ("📍 Nueva ruta", "NAV_START", [runShortcut("NAV — Iniciar ruta")]),
        ("🅿️ Dónde está mi auto", "CAR_FIND", [runShortcut("CAR — Dónde está mi auto")]),
        ("🎵 Shazam+", "SHAZAM", [runShortcut("MUSIC — Shazam+")]),
        ("🎶 Último Shazam", "LAST_SHAZAM", [runShortcut("MUSIC — Último Shazam")]),
        ("⚙️ Cambiar modo", "MODE_CHANGE", [runShortcut("SYS — Cambiar modo")])
    ])))

    shortcuts.append(("MENU — Casa", menuShortcut(mode: "Casa", rows: [
        ("↩️ Ver última selección", "LAST", getLastSelection(mode: "Casa")),
        ("📊 Estado de la casa", "HOME_STATE", [runShortcut("HOME — Estado de la casa")]),
        ("🔄 Actualizar sensores", "HOME_UPDATE", [runShortcut("HOME — Actualizar estado")]),
        ("💡 Luces", "LIGHTS", [runShortcut("Controlar casa")]),
        ("🚪 Puertas y accesorios", "DOORS", [runShortcut("Controlar casa 2")]),
        ("📹 Interfón", "CAMERAS", [runShortcut("Interfón")]),
        ("📜 Historial", "HISTORY", [runShortcut("HISTORY — Ver historial")]),
        ("⚙️ Cambiar modo", "MODE_CHANGE", [runShortcut("SYS — Cambiar modo")])
    ])))

    shortcuts.append(("MENU — Trabajo", menuShortcut(mode: "Trabajo", rows: [
        ("↩️ Ver última selección", "LAST", getLastSelection(mode: "Trabajo")),
        ("📱 Menú normal", "NORMAL_MENU", [runShortcut("MENU — Normal")]),
        ("🔕 Concentración", "FOCUS", [runShortcut("Focus")]),
        ("📜 Historial", "HISTORY", [runShortcut("HISTORY — Ver historial")]),
        ("⚙️ Cambiar modo", "MODE_CHANGE", [runShortcut("SYS — Cambiar modo")])
    ])))

    shortcuts.append(("MENU — Noche", menuShortcut(mode: "Noche", rows: [
        ("↩️ Ver última selección", "LAST", getLastSelection(mode: "Noche")),
        ("🏠 Buenas noches", "GOOD_NIGHT", [runShortcut("Buenas noches Siri")]),
        ("🏠 Casa", "HOME_MENU", [runShortcut("MENU — Casa")]),
        ("🎵 Shazam+", "SHAZAM", [runShortcut("MUSIC — Shazam+")]),
        ("⏰ Temporizador", "TIMER", [runShortcut("Iniciar temporizador")]),
        ("📜 Historial", "HISTORY", [runShortcut("HISTORY — Ver historial")]),
        ("⚙️ Cambiar modo", "MODE_CHANGE", [runShortcut("SYS — Cambiar modo")])
    ])))

    let locationID = uuid(), dateID = uuid(), parkingUUID = uuid()
    let latitudeProperty = [["Type": "WFPropertyVariableAggrandizement", "PropertyName": "Latitude"]]
    let longitudeProperty = [["Type": "WFPropertyVariableAggrandizement", "PropertyName": "Longitude"]]
    let altitudeProperty = [["Type": "WFPropertyVariableAggrandizement", "PropertyName": "Altitude"]]
    let accuracyProperty = [["Type": "WFPropertyVariableAggrandizement", "PropertyName": "Horizontal Accuracy"]]
    let nameProperty = [["Type": "WFPropertyVariableAggrandizement", "PropertyName": "Name"]]
    shortcuts.append(("CAR — Guardar estacionamiento", [
        systemAction("is.workflow.actions.getcurrentlocation", actionUUID: locationID),
        appIntent("GenerateUUIDIntent", actionUUID: parkingUUID),
        currentDate(dateID),
        setBool("CAR.ParkedValid", true),
        setText("CAR.ParkingID", outputText(parkingUUID, "Generate UUID")),
        appIntent("SetLocationVariableIntent", [
            "key": bywayString("CAR.ParkedLocation"),
            "latitude": outputAttachment(locationID, "Current Location", aggrandizements: latitudeProperty),
            "longitude": outputAttachment(locationID, "Current Location", aggrandizements: longitudeProperty),
            "name": outputText(locationID, "Current Location", aggrandizements: nameProperty),
            "altitude": outputAttachment(locationID, "Current Location", aggrandizements: altitudeProperty),
            "horizontalAccuracy": outputAttachment(locationID, "Current Location", aggrandizements: accuracyProperty)
        ]),
        setDate("CAR.ParkedAt", from: dateID),
        setText("CAR.ParkedSource", bywayString("MANUAL")),
        appendEvent(category: bywayString("CAR"), action: bywayString("PARK"), details: bywayString("{\"source\":\"MANUAL\"}")),
        notify("Ubicación del auto guardada.", title: "Estacionamiento")
    ]))

    let parkedID = uuid(), mapsID = uuid()
    let parkedTrue: [Action] = [
        appIntent("GetLocationVariableIntent", ["key": bywayString("CAR.ParkedLocation")], actionUUID: mapsID),
        systemAction("is.workflow.actions.openurl", ["WFInput": outputAttachment(mapsID, "Get Location Variable")])
    ]
    shortcuts.append(("CAR — Dónde está mi auto", [
        appIntent("GetBooleanVariableIntent", ["key": bywayString("CAR.ParkedValid")], actionUUID: parkedID)
    ] + ifBoolean(outputUUID: parkedID, outputName: "Get Boolean Variable", isTrue: true, then: parkedTrue, else: [show("No hay un estacionamiento guardado.")])))

    let destinationID = uuid(), tripUUID = uuid(), navDate = uuid()
    shortcuts.append(("NAV — Iniciar ruta", [
        ask("¿A dónde quieres ir?", actionUUID: destinationID),
        appIntent("GenerateUUIDIntent", actionUUID: tripUUID),
        currentDate(navDate),
        setBool("NAV.Active", true),
        setText("NAV.SessionID", outputText(tripUUID, "Generate UUID")),
        setText("NAV.Destination", outputText(destinationID, "Provided Input")),
        setText("NAV.Name", outputText(destinationID, "Provided Input")),
        setInteger("NAV.ResumeCount", 0),
        setDate("NAV.StartedAt", from: navDate),
        setDate("NAV.LastUpdatedAt", from: navDate),
        appendEvent(category: bywayString("NAV"), action: bywayString("ROUTE_START"), details: outputText(destinationID, "Provided Input", prefix: "{\"destination\":\"", suffix: "\"}")),
        systemAction("is.workflow.actions.searchmaps", ["WFInput": outputAttachment(destinationID, "Provided Input")])
    ]))

    let navActiveID = uuid(), navDestinationID = uuid(), resumeDate = uuid()
    let resumeTrue: [Action] = [
        appIntent("GetTextVariableIntent", ["key": bywayString("NAV.Destination")], actionUUID: navDestinationID),
        appIntent("IncrementVariableIntent", ["key": bywayString("NAV.ResumeCount"), "amount": 1.0]),
        currentDate(resumeDate),
        setDate("NAV.LastUpdatedAt", from: resumeDate),
        appendEvent(category: bywayString("NAV"), action: bywayString("ROUTE_RESUME"), details: bywayString("{}")),
        systemAction("is.workflow.actions.searchmaps", ["WFInput": outputAttachment(navDestinationID, "Get Text Variable")])
    ]
    shortcuts.append(("NAV — Reanudar ruta", [
        appIntent("GetBooleanVariableIntent", ["key": bywayString("NAV.Active")], actionUUID: navActiveID)
    ] + ifBoolean(outputUUID: navActiveID, outputName: "Get Boolean Variable", isTrue: true, then: resumeTrue, else: [show("No tienes una ruta pendiente.")])))

    let endDate = uuid()
    shortcuts.append(("NAV — Finalizar ruta", [
        currentDate(endDate),
        setBool("NAV.Active", false),
        setDate("NAV.LastUpdatedAt", from: endDate),
        appendEvent(category: bywayString("NAV"), action: bywayString("ROUTE_END"), details: bywayString("{}")),
        notify("Ruta finalizada.", title: "Navegación")
    ]))

    let shazamRun = uuid(), shazamDate = uuid(), shazamUUID = uuid()
    let runShazam = runShortcut("Add Shazam to Music Library", actionUUID: shazamRun)
    shortcuts.append(("MUSIC — Shazam+", [
        runShazam,
        appIntent("GenerateUUIDIntent", actionUUID: shazamUUID),
        currentDate(shazamDate),
        setBool("MUSIC.HasLast", true),
        setText("MUSIC.LastID", outputText(shazamUUID, "Generate UUID")),
        setText("MUSIC.LastTitle", outputText(shazamRun, "Shortcut Result")),
        setDate("MUSIC.LastShazamAt", from: shazamDate),
        setBool("MUSIC.LastAddedToLibrary", true),
        appendEvent(category: bywayString("MUSIC"), action: bywayString("SHAZAM"), details: bywayString("{\"addedToLibrary\":true}")),
        notify("Canción reconocida y añadida a la biblioteca.", title: "Shazam+")
    ]))

    let hasMusicID = uuid(), lastTitleID = uuid()
    let musicTrue: [Action] = [
        appIntent("GetTextVariableIntent", ["key": bywayString("MUSIC.LastTitle")], actionUUID: lastTitleID),
        show(outputText(lastTitleID, "Get Text Variable", prefix: "🎵 "))
    ]
    shortcuts.append(("MUSIC — Último Shazam", [
        appIntent("GetBooleanVariableIntent", ["key": bywayString("MUSIC.HasLast")], actionUUID: hasMusicID)
    ] + ifBoolean(outputUUID: hasMusicID, outputName: "Get Boolean Variable", isTrue: true, then: musicTrue, else: [show("Todavía no hay ninguna canción.")])))

    func historyBranch(category: String?) -> [Action] {
        let queryID = uuid()
        var parameters: [String: Any] = [
            "key": bywayString("HISTORY.Events"),
            "limit": 50,
            "order": "newestFirst"
        ]
        if let category { parameters["category"] = bywayString(category) }
        return [
            appIntent("QueryEventsIntent", parameters, actionUUID: queryID),
            show(outputText(queryID, "Query Events"))
        ]
    }
    shortcuts.append(("HISTORY — Ver historial", chooseMenu(prompt: "Historial de Byway", items: [
        ("📋 Todo", historyBranch(category: nil)),
        ("🎵 Música", historyBranch(category: "MUSIC")),
        ("🗺️ Navegación", historyBranch(category: "NAV")),
        ("🅿️ Auto", historyBranch(category: "CAR")),
        ("🏠 Casa", historyBranch(category: "HOME")),
        ("⚙️ Sistema", historyBranch(category: "SYS"))
    ])))

    let homeInputID = uuid()
    shortcuts.append(("HOME — Procesar estado", [
        ask("Pega el estado del accesorio como JSON", actionUUID: homeInputID),
        appIntent("SetDictionaryEntryIntent", [
            "key": bywayString("HOME.State"),
            "field": bywayString("Manual.LastUpdate"),
            "jsonValue": outputText(homeInputID, "Provided Input")
        ]),
        appendEvent(category: bywayString("HOME"), action: bywayString("STATE_CHANGE"), details: bywayString("{\"source\":\"MANUAL\"}"))
    ]))

    let homeInitDate = uuid()
    shortcuts.append(("HOME — Inicializar estado", [
        runShortcut("Controlar casa"),
        currentDate(homeInitDate),
        setBool("HOME.Initialized", true),
        setDate("HOME.LastSyncAt", from: homeInitDate),
        appendEvent(category: bywayString("HOME"), action: bywayString("INITIALIZE"), details: bywayString("{}")),
        notify("Estado de Casa inicializado.")
    ]))

    let homeUpdateDate = uuid()
    shortcuts.append(("HOME — Actualizar estado", [
        runShortcut("Controlar casa 2"),
        currentDate(homeUpdateDate),
        setDate("HOME.LastSyncAt", from: homeUpdateDate),
        appendEvent(category: bywayString("HOME"), action: bywayString("SYNC"), details: bywayString("{}")),
        notify("Estado de Casa actualizado.")
    ]))

    let homeStateID = uuid()
    shortcuts.append(("HOME — Estado de la casa", [
        appIntent("GetJSONVariableIntent", ["key": bywayString("HOME.State")], actionUUID: homeStateID),
        show(outputText(homeStateID, "Get Variable as JSON", prefix: "🏠 Casa\n\n"))
    ]))

    for mode in ["Auto", "Casa", "Trabajo", "Noche", "Normal"] {
        shortcuts.append(("Modo \(mode)", modeActions(mode)))
    }
    return shortcuts
}

enum GeneratorError: LocalizedError {
    case usage
    var errorDescription: String? { "Usage: GenerateWorkflowShortcuts <output-directory>" }
}

do {
    guard CommandLine.arguments.count == 2 else { throw GeneratorError.usage }
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let shortcuts = buildShortcuts()
    guard shortcuts.count == 30 else {
        throw NSError(domain: "BywayWorkflowGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 30 shortcuts, found \(shortcuts.count)."])
    }
    for (name, actions) in shortcuts {
        let data = try PropertyListSerialization.data(fromPropertyList: workflow(actions), format: .xml, options: 0)
        try data.write(to: output.appendingPathComponent("\(name).shortcut"), options: .atomic)
    }
    print("Generated \(shortcuts.count) unsigned shortcuts in \(output.path)")
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
