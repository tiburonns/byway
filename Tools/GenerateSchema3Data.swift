import CryptoKit
import Foundation

enum SchemaGeneratorError: LocalizedError {
    case usage
    var errorDescription: String? { "Usage: GenerateSchema3Data <output-directory> <archive.byway>" }
}

func filename(for key: String) -> String {
    let normalized = key
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .precomposedStringWithCanonicalMapping
        .lowercased()
    return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
}

@main
enum GenerateSchema3Data {
static func main() {
do {
    guard CommandLine.arguments.count == 3 else { throw SchemaGeneratorError.usage }
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let archiveURL = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let now = Date()
    let variables: [GlobalVariable] = [
        GlobalVariable(key: "SYS.SchemaVersion", value: .integer(3), createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.Initialized", value: .boolean(true), createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.Mode", value: .text("Normal"), createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.ModeChangedAt", value: .date(now), createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.LastAction", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.LastActionAt", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.LastSource", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "SYS.Settings", value: .dictionary([
            "historyEnabled": .boolean(true),
            "rememberMenuSelection": .boolean(true),
            "autoSaveParking": .boolean(true),
            "navigationResume": .boolean(true),
            "autoAddShazam": .boolean(true),
            "homeLoggingEnabled": .boolean(true),
            "notificationsEnabled": .boolean(true)
        ]), createdAt: now, updatedAt: now),
        GlobalVariable(key: "UI.LastSelection", value: .dictionary([:]), createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.Active", value: .boolean(false), createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.SessionID", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.Destination", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.Name", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.Transport", value: .text("Driving"), createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.Provider", value: .text("AppleMaps"), createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.StartedAt", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.LastUpdatedAt", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "NAV.ResumeCount", value: .integer(0), createdAt: now, updatedAt: now),
        GlobalVariable(key: "CAR.ParkedValid", value: .boolean(false), createdAt: now, updatedAt: now),
        GlobalVariable(key: "CAR.ParkingID", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "CAR.ParkedLocation", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "CAR.ParkedAt", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "CAR.ParkedAddress", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "CAR.ParkedSource", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.HasLast", value: .boolean(false), createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastID", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastTitle", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastArtist", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastAlbum", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastURL", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastShazamAt", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "MUSIC.LastAddedToLibrary", value: .boolean(false), createdAt: now, updatedAt: now),
        GlobalVariable(key: "HOME.Initialized", value: .boolean(false), createdAt: now, updatedAt: now),
        GlobalVariable(key: "HOME.State", value: .dictionary([:]), createdAt: now, updatedAt: now),
        GlobalVariable(key: "HOME.LastSyncAt", value: .null, createdAt: now, updatedAt: now),
        GlobalVariable(key: "HISTORY.Events", value: .array([]), createdAt: now, updatedAt: now)
    ]
    guard variables.count == 36 else {
        throw NSError(domain: "BywaySchemaGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 36 variables, found \(variables.count)."])
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    for variable in variables {
        try encoder.encode(variable).write(to: output.appendingPathComponent(filename(for: variable.key)), options: .atomic)
    }
    let archive = BywayArchive(exportedAt: now, variables: variables, attachments: [:], folders: [])
    try encoder.encode(archive).write(to: archiveURL, options: .atomic)
    print("Generated 36 Schema 3 variables and \(archiveURL.path)")
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
}
}
