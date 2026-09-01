import Foundation

let shortcutNames: [String: String] = [
    "BYWAY — Inicializar sistema": "BYWAY — Initialize System",
    "DB — Registrar evento": "DB — Log Event",
    "SYS — Establecer modo": "SYS — Set Mode",
    "SYS — Cambiar modo": "SYS — Change Mode",
    "SYS — Qué modo tengo": "SYS — Current Mode",
    "UI — Guardar selección": "UI — Save Selection",
    "UI — Obtener última selección": "UI — Get Last Selection",
    "AB — Principal": "AB — Main",
    "MENU — Normal": "MENU — Normal",
    "MENU — Auto": "MENU — Driving",
    "MENU — Casa": "MENU — Home",
    "MENU — Trabajo": "MENU — Work",
    "MENU — Noche": "MENU — Night",
    "CAR — Guardar estacionamiento": "CAR — Save Parking",
    "CAR — Dónde está mi auto": "CAR — Find My Car",
    "NAV — Iniciar ruta": "NAV — Start Route",
    "NAV — Reanudar ruta": "NAV — Resume Route",
    "NAV — Finalizar ruta": "NAV — End Route",
    "MUSIC — Shazam+": "MUSIC — Shazam+",
    "MUSIC — Último Shazam": "MUSIC — Last Shazam",
    "HISTORY — Ver historial": "HISTORY — View History",
    "HOME — Procesar estado": "HOME — Process State",
    "HOME — Inicializar estado": "HOME — Initialize State",
    "HOME — Actualizar estado": "HOME — Update State",
    "HOME — Estado de la casa": "HOME — Home Status",
    "Modo Auto": "Driving Mode",
    "Modo Casa": "Home Mode",
    "Modo Trabajo": "Work Mode",
    "Modo Noche": "Night Mode",
    "Modo Normal": "Normal Mode"
]

let exact: [String: String] = [
    "Inicializa el esquema 3 de Byway sin sobrescribir valores existentes.": "Initializes Byway Schema 3 without overwriting existing values.",
    "Esquema 3 listo: 36 variables verificadas.": "Schema 3 is ready: 36 variables verified.",
    "Byway inicializado": "Byway initialized",
    "Categoría del evento (SYS, UI, CAR, NAV, MUSIC o HOME)": "Event category (SYS, UI, CAR, NAV, MUSIC, or HOME)",
    "Acción del evento": "Event action",
    "Origen (SIRI, ACTION_BUTTON, MENU, CARPLAY, AUTOMATION, HOME o MANUAL)": "Source (SIRI, ACTION_BUTTON, MENU, CARPLAY, AUTOMATION, HOME, or MANUAL)",
    "Evento guardado.": "Event saved.",
    "Selecciona el modo": "Choose a mode",
    "Estás en modo ￼.": "Current mode: ￼.",
    "Clave de selección, por ejemplo Auto.Portrait": "Selection key, for example Auto.Portrait",
    "Valor JSON, por ejemplo \"NAV_RESUME\"": "JSON value, for example \"NAV_RESUME\"",
    "Selección guardada.": "Selection saved.",
    "AUTO · ¿Qué quieres hacer?": "DRIVING · What do you want to do?",
    "CASA · ¿Qué quieres hacer?": "HOME · What do you want to do?",
    "TRABAJO · ¿Qué quieres hacer?": "WORK · What do you want to do?",
    "NOCHE · ¿Qué quieres hacer?": "NIGHT · What do you want to do?",
    "NORMAL · ¿Qué quieres hacer?": "NORMAL · What do you want to do?",
    "Historial de Byway": "Byway History",
    "¿A dónde quieres ir?": "Where do you want to go?",
    "Navegación": "Navigation",
    "Estacionamiento": "Parking",
    "Ubicación del auto guardada.": "Car location saved.",
    "No hay un estacionamiento guardado.": "No saved parking location.",
    "No tienes una ruta pendiente.": "You do not have a pending route.",
    "Ruta finalizada.": "Route ended.",
    "Canción reconocida y añadida a la biblioteca.": "Song recognized and added to the library.",
    "Todavía no hay ninguna canción.": "No song has been recognized yet.",
    "Pega el estado del accesorio como JSON": "Paste the accessory state as JSON",
    "Estado de Casa inicializado.": "Home status initialized.",
    "Estado de Casa actualizado.": "Home status updated.",
    "↩️ Ver última selección": "↩️ View last selection",
    "▶️ Reanudar ruta": "▶️ Resume route",
    "⚙️ Ajustes rápidos": "⚙️ Quick settings",
    "⚙️ Cambiar modo": "⚙️ Change mode",
    "⚙️ Sistema": "⚙️ System",
    "🅿️ Dónde está mi auto": "🅿️ Find my car",
    "🎶 Último Shazam": "🎶 Last Shazam",
    "🏠 Buenas noches": "🏠 Good night",
    "🏠 Casa": "🏠 Home",
    "💡 Luces": "💡 Lights",
    "💼 Trabajo": "💼 Work",
    "📊 Estado de la casa": "📊 Home status",
    "📋 Todo": "📋 All",
    "📍 Nueva ruta": "📍 New route",
    "📜 Historial": "📜 History",
    "📱 Menú normal": "📱 Normal menu",
    "📹 Interfón": "📹 Intercom",
    "🔄 Actualizar sensores": "🔄 Update sensors",
    "🔄 Cambiar modo": "🔄 Change mode",
    "🔕 Concentración": "🔕 Focus",
    "🗺️ Navegación": "🗺️ Navigation",
    "🚪 Puertas y accesorios": "🚪 Doors and accessories",
    "🚗 Auto": "🚗 Driving",
    "🅿️ Auto": "🅿️ Car",
    "🏠 Casa\n\n￼": "🏠 Home\n\n￼",
    "🌙 Noche": "🌙 Night",
    "Última selección de Auto: ￼": "Last Driving selection: ￼",
    "Última selección de Casa: ￼": "Last Home selection: ￼",
    "Última selección de Trabajo: ￼": "Last Work selection: ￼",
    "Última selección de Noche: ￼": "Last Night selection: ￼",
    "Última selección de Normal: ￼": "Last Normal selection: ￼",
    "Activa el modo Auto y registra el cambio.": "Activates Driving mode and records the change.",
    "Activa el modo Casa y registra el cambio.": "Activates Home mode and records the change.",
    "Activa el modo Trabajo y registra el cambio.": "Activates Work mode and records the change.",
    "Activa el modo Noche y registra el cambio.": "Activates Night mode and records the change.",
    "Activa el modo Normal y registra el cambio.": "Activates Normal mode and records the change.",
    "Modo Auto activado.": "Driving mode activated.",
    "Modo Casa activado.": "Home mode activated.",
    "Modo Trabajo activado.": "Work mode activated.",
    "Modo Noche activado.": "Night mode activated.",
    "Modo Normal activado.": "Normal mode activated."
]

func localized(_ string: String) -> String {
    shortcutNames[string] ?? exact[string] ?? string
}

func localize(_ value: Any) -> Any {
    if let string = value as? String { return localized(string) }
    if let array = value as? [Any] { return array.map(localize) }
    if let dictionary = value as? [String: Any] {
        return dictionary.mapValues(localize)
    }
    return value
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: swift LocalizeWorkflowShortcuts.swift INPUT_DIR OUTPUT_DIR\n".utf8))
    exit(2)
}

let fileManager = FileManager.default
let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

for file in try fileManager.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter({ $0.pathExtension == "shortcut" }) {
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), options: [], format: nil)
    let translated = localize(plist)
    let data = try PropertyListSerialization.data(fromPropertyList: translated, format: .binary, options: 0)
    let sourceName = file.deletingPathExtension().lastPathComponent
    let destinationName = shortcutNames[sourceName] ?? sourceName
    try data.write(to: output.appendingPathComponent(destinationName).appendingPathExtension("shortcut"), options: .atomic)
}

print("Localized \(shortcutNames.count) workflow names into \(output.path)")
