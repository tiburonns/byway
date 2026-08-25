import AppIntents
import Foundation
import UniformTypeIdentifiers

struct ExportVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Variables"
    static let description = IntentDescription("Export all variables and stored files as a portable byway archive.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let data = try await VariableRepository.shared.exportArchive()
        let file = IntentFile(
            data: data,
            filename: "byway-backup.byway",
            type: .bywayArchive
        )
        return .result(value: file, dialog: "Exported all byway variables.")
    }
}

struct ImportVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Variables"
    static let description = IntentDescription("Import variables and files from a byway archive.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Archive",
        supportedContentTypes: [.bywayArchive, .json],
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var archive: IntentFile
    @Parameter(title: "Import Mode", default: .overwrite) var mode: ImportMode

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let url = archive.fileURL else {
            throw BywayError.invalidValue("Shortcuts did not provide a readable archive.")
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let count = try await VariableRepository.shared.importArchive(
            data: Data(contentsOf: url),
            strategy: mode.strategy
        )
        return .result(value: count, dialog: "Imported \(count) variables.")
    }
}
