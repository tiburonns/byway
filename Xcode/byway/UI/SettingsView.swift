import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(VariableStore.self) private var store
    @State private var exportDocument = ArchiveDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importStrategy: ImportStrategy = .overwrite
    @State private var statusMessage: String?
    @AppStorage(AppLanguage.storageKey) private var languageValue = AppLanguage.system.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("App language", selection: $languageValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.titleKey).tag(language.rawValue)
                    }
                }
            }

            Section("Storage") {
                LabeledContent("Location") {
                    Label(
                        store.storageStatus?.location == .iCloud ? "Private iCloud" : "On this device",
                        systemImage: store.storageStatus?.location == .iCloud ? "icloud.fill" : "iphone"
                    )
                }
                LabeledContent("Variables", value: store.variables.count.formatted())
                Text("When iCloud Drive is available, data syncs through your private iCloud container. It is never uploaded to a byway server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Backup and sharing") {
                Picker("When importing", selection: $importStrategy) {
                    ForEach(ImportStrategy.allCases) { strategy in
                        Text(LocalizedStringKey(strategy.title)).tag(strategy)
                    }
                }

                Button {
                    Task { await prepareExport() }
                } label: {
                    Label("Export all variables", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("Import a byway archive", systemImage: "square.and.arrow.down")
                }
            }

            Section("Maintenance") {
                Button("Remove expired variables") {
                    Task {
                        do {
                            let count = try await store.removeExpired()
                            statusMessage = localizedCount(
                                count,
                                singular: "Removed %lld expired variable.",
                                plural: "Removed %lld expired variables."
                            )
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
            }

            Section("Shortcuts") {
                Text("Open Shortcuts and search for “byway” to use typed variables, atomic transactions, structured events, dictionary paths, list operations, metadata, UUIDs, and portable archives.")
                    .font(.callout)
            }

            Section("Privacy") {
                Label("No account and no analytics", systemImage: "hand.raised.fill")
                Text("Your variables remain in the app sandbox or your private iCloud Drive container.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .bywayArchive,
            defaultFilename: "byway-backup"
        ) { result in
            if case .failure(let error) = result { statusMessage = error.localizedDescription }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.bywayArchive, .json],
            allowsMultipleSelection: false
        ) { result in
            Task { await importFile(result) }
        }
        .alert("byway", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func prepareExport() async {
        do {
            exportDocument = ArchiveDocument(data: try await store.exportArchive())
            isExporting = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let count = try await store.importArchive(Data(contentsOf: url), strategy: importStrategy)
            statusMessage = localizedCount(
                count,
                singular: "Imported %lld variable.",
                plural: "Imported %lld variables."
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func localizedCount(_ count: Int, singular: String, plural: String) -> String {
        let language = AppLanguage(rawValue: languageValue) ?? .system
        let key = count == 1 ? singular : plural
        let format = String(localized: String.LocalizationValue(key), locale: language.locale)
        return String.localizedStringWithFormat(format, count)
    }
}
