import SwiftUI

struct VariableDetailView: View {
    @Environment(VariableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let variableID: UUID
    @State private var isEditing = false

    private var variable: GlobalVariable? {
        store.variables.first { $0.id == variableID }
    }

    var body: some View {
        Group {
            if let variable {
                List {
                    Section("Value") {
                        ValuePreview(value: variable.value)
                    }

                    if !variable.tags.isEmpty || !variable.notes.isEmpty {
                        Section("Metadata") {
                            if !variable.tags.isEmpty {
                                LabeledContent("Tags", value: variable.tags.joined(separator: ", "))
                            }
                            if !variable.notes.isEmpty {
                                Text(variable.notes)
                            }
                        }
                    }

                    Section("Details") {
                        LabeledContent("Type") {
                            Text(LocalizedStringKey(variable.value.kind.title))
                        }
                        LabeledContent("Revision", value: variable.revision.formatted())
                        LabeledContent("Last updated") {
                            Text(variable.updatedAt, format: .dateTime)
                        }
                        if let expiresAt = variable.expiresAt {
                            LabeledContent("Expires") {
                                Text(expiresAt, format: .dateTime)
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            Task {
                                await store.delete(variable)
                                dismiss()
                            }
                        } label: {
                            Label("Delete variable", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle(variable.key)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { isEditing = true }
                    }
                }
                .sheet(isPresented: $isEditing) {
                    NavigationStack { VariableEditorView(variable: variable) }
                }
            } else {
                ContentUnavailableView("Variable unavailable", systemImage: "questionmark.folder")
            }
        }
    }
}

private struct ValuePreview: View {
    let value: VariableValue

    var body: some View {
        switch value {
        case .boolean(let value):
            Label(LocalizedStringKey(value ? "True" : "False"), systemImage: value ? "checkmark.circle.fill" : "xmark.circle")
        case .date(let value):
            Text(value, format: .dateTime)
        case .location(let location):
            VStack(alignment: .leading, spacing: 4) {
                if let name = location.name { Text(name).font(.headline) }
                Text("\(location.latitude.formatted()), \(location.longitude.formatted())")
                    .textSelection(.enabled)
            }
        case .url(let url):
            Link(url.absoluteString, destination: url)
        case .array, .dictionary:
            Text(value.jsonString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        case .data(let data):
            Text(data.base64EncodedString())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        default:
            Text(value.summary).textSelection(.enabled)
        }
    }
}
