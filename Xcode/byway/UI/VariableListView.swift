import SwiftUI

private struct EditorDestination: Identifiable {
    let id = UUID()
    var variable: GlobalVariable?
}

struct VariableListView: View {
    @Environment(VariableStore.self) private var store
    @State private var searchText = ""
    @State private var editor: EditorDestination?

    private var filteredVariables: [GlobalVariable] {
        guard !searchText.isEmpty else { return store.variables }
        return store.variables.filter {
            $0.key.localizedCaseInsensitiveContains(searchText)
                || $0.notes.localizedCaseInsensitiveContains(searchText)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        Group {
            if store.isLoading && store.variables.isEmpty {
                ProgressView("Loading variables…")
            } else if store.variables.isEmpty {
                ContentUnavailableView {
                    Label("No variables", systemImage: "shippingbox")
                } description: {
                    Text("Create one here or use a byway action in Shortcuts.")
                } actions: {
                    Button("Create variable") { editor = EditorDestination() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(filteredVariables) { variable in
                    NavigationLink(value: variable.id) {
                        VariableRow(variable: variable)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await store.setFavorite(!variable.isFavorite, for: variable) }
                        } label: {
                            Label(
                                variable.isFavorite ? "Unfavorite" : "Favorite",
                                systemImage: variable.isFavorite ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.delete(variable) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.inset)
                .refreshable { await store.refresh() }
            }
        }
        .navigationTitle("byway")
        .searchable(text: $searchText, prompt: "Keys, tags, or notes")
        .navigationDestination(for: UUID.self) { id in
            VariableDetailView(variableID: id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editor = EditorDestination() } label: {
                    Label("New variable", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { destination in
            NavigationStack {
                VariableEditorView(variable: destination.variable)
            }
        }
        .alert("byway", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct VariableRow: View {
    let variable: GlobalVariable

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: variable.value.kind.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(variable.key).font(.headline)
                    if variable.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(variable.value.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(variable.value.kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
