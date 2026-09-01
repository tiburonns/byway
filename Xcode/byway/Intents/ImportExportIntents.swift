import AppIntents
import Foundation
import UniformTypeIdentifiers

struct ExportVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Variables"
    static let description = IntentDescription("Export all variables and stored files as a portable byway archive.")
    static let openAppWhenRun = false

    @Parameter(title: "Keys") var keys: [String]?

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let requestedKeys = keys.map(Set.init)
        let data = try await VariableRepository.shared.exportArchive(variableKeys: requestedKeys)
        let file = IntentFile(
            data: data,
            filename: "byway-backup.byway",
            type: .bywayArchive
        )
        return .result(
            value: file,
            dialog: requestedKeys == nil ? "Exported all byway variables." : "Exported \(requestedKeys!.count) requested variables."
        )
    }
}

struct ImportVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Variables"
    static let description = IntentDescription("Import variables and files from a byway archive.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Archive",
        supportedTypeIdentifiers: ["com.tiburonns.byway.archive", "public.json"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    ) var archive: IntentFile
    @Parameter(title: "Import Mode", default: .overwrite) var mode: ImportMode

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let count = try await VariableRepository.shared.importArchive(
            data: IntentSupport.data(for: archive),
            strategy: mode.strategy
        )
        return .result(value: count, dialog: "Imported \(count) variables.")
    }
}
