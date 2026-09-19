import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private struct PendingImport: Identifiable {
        let id = UUID()
        var data: Data
        var preview: ArchivePreview
        var passphrase: String?
    }

    @Environment(VariableStore.self) private var store
    @State private var exportDocument = ArchiveDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importStrategy: ImportStrategy = .overwrite
    @State private var encryptExport = false
    @State private var exportPassphrase = ""
    @State private var importPassphrase = ""
    @State private var pendingImport: PendingImport?
    @State private var canUndoImport = false
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

                Toggle("Encrypt exported archive", isOn: $encryptExport)
                if encryptExport {
                    SecureField("Export passphrase (8+ characters)", text: $exportPassphrase)
                        .textContentType(.newPassword)
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


                SecureField("Import passphrase, if encrypted", text: $importPassphrase)
                    .textContentType(.password)

                Button(role: .destructive) {
                    Task { await undoLastImport() }
                } label: {
                    Label("Undo last import", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(!canUndoImport)

                Text("Every import is previewed first. A successful import keeps one local recovery point so it can be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                if store.quarantinedFileCount > 0 {
                    LabeledContent(
                        "Recovered damaged files",
                        value: store.quarantinedFileCount.formatted()
                    )
                    Text("Damaged storage records are preserved in Byway's Quarantine folder instead of being deleted silently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            contentType: encryptExport ? .bywayEncryptedArchive : .bywayArchive,
            defaultFilename: encryptExport ? "byway-backup.bywaye" : "byway-backup"
        ) { result in
            if case .failure(let error) = result { statusMessage = error.localizedDescription }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.bywayArchive, .bywayEncryptedArchive, .json, .data],
            allowsMultipleSelection: false
        ) { result in
            Task { await importFile(result) }
        }
        .sheet(item: $pendingImport) { pending in
            NavigationStack {
                Form {
                    Section("Import preview") {
                        LabeledContent("Archive version", value: pending.preview.archiveVersion.formatted())
                        LabeledContent("Variables in archive", value: pending.preview.totalVariables.formatted())
                        LabeledContent("Will import", value: pending.preview.variablesToImport.formatted())
                        if pending.preview.skippedExisting > 0 {
                            LabeledContent("Will skip", value: pending.preview.skippedExisting.formatted())
                        }
                        if pending.preview.overwrittenExisting > 0 {
                            LabeledContent("Will overwrite", value: pending.preview.overwrittenExisting.formatted())
                        }
                        if pending.preview.removedExisting > 0 {
                            LabeledContent("Will remove", value: pending.preview.removedExisting.formatted())
                        }
                        LabeledContent("Attachments", value: pending.preview.attachments.formatted())
                        LabeledContent("Attachment size") {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(pending.preview.attachmentBytes), countStyle: .file))
                        }
                        LabeledContent("Protection", value: pending.preview.isEncrypted ? "Encrypted" : "Not encrypted")
                    }
                }
                .navigationTitle("Confirm import")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { pendingImport = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { await confirmImport(pending) } }
                    }
                }
            }
        }
        .task { await refreshUndoAvailability() }
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
            let data = if encryptExport {
                try await store.exportEncryptedArchive(passphrase: exportPassphrase)
            } else {
                try await store.exportArchive()
            }
            exportDocument = ArchiveDocument(data: data)
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
            let data = try Data(contentsOf: url)
            let passphrase = importPassphrase.isEmpty ? nil : importPassphrase
            let preview = try await store.previewArchive(data, strategy: importStrategy, passphrase: passphrase)
            pendingImport = PendingImport(data: data, preview: preview, passphrase: passphrase)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func confirmImport(_ pending: PendingImport) async {
        pendingImport = nil
        do {
            let count = try await store.importArchive(
                pending.data,
                strategy: importStrategy,
                passphrase: pending.passphrase
            )
            importPassphrase = ""
            await refreshUndoAvailability()
            statusMessage = localizedCount(
                count,
                singular: "Imported %lld variable.",
                plural: "Imported %lld variables."
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func undoLastImport() async {
        do {
            try await store.undoLastImport()
            await refreshUndoAvailability()
            statusMessage = "The last import was undone. You can use Undo again to restore the imported state."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshUndoAvailability() async {
        canUndoImport = (try? await store.canUndoLastImport()) ?? false
    }

    private func localizedCount(_ count: Int, singular: String, plural: String) -> String {
        let language = AppLanguage(rawValue: languageValue) ?? .system
        let key = count == 1 ? singular : plural
        let format = String(localized: String.LocalizationValue(key), locale: language.locale)
        return String.localizedStringWithFormat(format, count)
    }
}
