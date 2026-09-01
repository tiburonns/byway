import SwiftUI

private struct EditorDestination: Identifiable {
    let id = UUID()
    var variable: GlobalVariable?
}

private enum FolderFilter: Hashable {
    case all
    case unfiled
    case folder(UUID)
}

struct VariableListView: View {
    @Environment(VariableStore.self) private var store
    @Environment(\.editMode) private var editMode
    @State private var searchText = ""
    @State private var editor: EditorDestination?
    @State private var folderFilter: FolderFilter = .all
    @State private var selection = Set<UUID>()
    @State private var showsFolderManager = false
    @State private var showsMoveDialog = false
    @State private var showsDeleteConfirmation = false

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var filteredVariables: [GlobalVariable] {
        store.variables.filter { variable in
            let matchesFolder: Bool
            switch folderFilter {
            case .all: matchesFolder = true
            case .unfiled: matchesFolder = variable.folderID == nil
            case .folder(let id): matchesFolder = variable.folderID == id
            }
            let matchesSearch = searchText.isEmpty
                || variable.key.localizedCaseInsensitiveContains(searchText)
                || variable.notes.localizedCaseInsensitiveContains(searchText)
                || variable.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesFolder && matchesSearch
        }
    }

    private var filterTitle: String {
        switch folderFilter {
        case .all: "All variables"
        case .unfiled: "No folder"
        case .folder(let id): store.folders.first(where: { $0.id == id })?.name ?? "Folder"
        }
    }

    var body: some View {
        Group {
            if store.isLoading && store.variables.isEmpty && store.folders.isEmpty {
                ProgressView("Loading variables…")
            } else if store.variables.isEmpty && store.folders.isEmpty {
                ContentUnavailableView {
                    Label("No variables", systemImage: "shippingbox")
                } description: {
                    Text("Create a variable or folder here, or use a byway action in Shortcuts.")
                } actions: {
                    Button("Create variable") { editor = EditorDestination() }
                        .buttonStyle(.borderedProminent)
                    Button("Create folder") { showsFolderManager = true }
                }
            } else {
                List(selection: $selection) {
                    if filteredVariables.isEmpty {
                        ContentUnavailableView.search(text: searchText.isEmpty ? filterTitle : searchText)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredVariables) { variable in
                            variableRow(variable)
                                .tag(variable.id)
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
            if !store.variables.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        folderFilter = .all
                    } label: {
                        Label("All variables", systemImage: folderFilter == .all ? "checkmark" : "tray.full")
                    }
                    Button {
                        folderFilter = .unfiled
                    } label: {
                        Label("No folder", systemImage: folderFilter == .unfiled ? "checkmark" : "tray")
                    }
                    if !store.folders.isEmpty { Divider() }
                    ForEach(store.folders) { folder in
                        Button {
                            folderFilter = .folder(folder.id)
                        } label: {
                            Label(folder.name, systemImage: folderFilter == .folder(folder.id) ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(filterTitle), systemImage: "folder")
                }

                Menu {
                    Button { editor = EditorDestination() } label: {
                        Label("New variable", systemImage: "plus")
                    }
                    Button { showsFolderManager = true } label: {
                        Label("Manage folders", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            if isEditing && !selection.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { showsMoveDialog = true } label: {
                        Label("Move", systemImage: "folder")
                    }
                    Spacer()
                    Text("\(selection.count) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(item: $editor) { destination in
            NavigationStack {
                VariableEditorView(variable: destination.variable)
            }
        }
        .sheet(isPresented: $showsFolderManager) {
            FolderManagementView()
        }
        .confirmationDialog(
            "Move \(selection.count) variables",
            isPresented: $showsMoveDialog,
            titleVisibility: .visible
        ) {
            Button("No folder") { moveSelection(to: nil) }
            ForEach(store.folders) { folder in
                Button(folder.name) { moveSelection(to: folder.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the destination folder.")
        }
        .alert(
            "Delete \(selection.count) variables?",
            isPresented: $showsDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected variables. You can restore recent values from History.")
        }
        .alert("byway", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.folders) { _, folders in
            if case .folder(let id) = folderFilter, !folders.contains(where: { $0.id == id }) {
                folderFilter = .all
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { selection.removeAll() }
        }
    }

    @ViewBuilder
    private func variableRow(_ variable: GlobalVariable) -> some View {
        let folderName = store.folders.first(where: { $0.id == variable.folderID })?.name
        if isEditing {
            VariableRow(variable: variable, folderName: folderName)
        } else {
            NavigationLink(value: variable.id) {
                VariableRow(variable: variable, folderName: folderName)
            }
            .swipeActions(edge: .leading) {
                Button {
                    Task { await store.setFavorite(!variable.isFavorite, for: variable) }
                } label: {
                    Label(LocalizedStringKey(variable.isFavorite ? "Unfavorite" : "Favorite"), systemImage: variable.isFavorite ? "star.slash" : "star")
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
    }

    private func moveSelection(to folderID: UUID?) {
        let ids = selection
        Task {
            do {
                try await store.moveVariables(ids: ids, to: folderID)
                selection.removeAll()
                editMode?.wrappedValue = .inactive
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelection() {
        let ids = selection
        Task {
            do {
                try await store.deleteVariables(ids: ids)
                selection.removeAll()
                editMode?.wrappedValue = .inactive
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct FolderManagementView: View {
    @Environment(VariableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newFolderName = ""
    @State private var folderToRename: VariableFolder?
    @State private var renamedFolderName = ""
    @State private var folderToDelete: VariableFolder?

    var body: some View {
        NavigationStack {
            Form {
                Section("New folder") {
                    HStack {
                        TextField("Folder name", text: $newFolderName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(createFolder)
                        Button("Create", action: createFolder)
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    if store.folders.isEmpty {
                        Text("No folders yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.folders) { folder in
                        folderRow(folder)
                    }
                } header: {
                    Text("Folders")
                } footer: {
                    Text("Deleting a folder keeps its variables and moves them to No Folder.")
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename folder", isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )) {
                TextField("Folder name", text: $renamedFolderName)
                Button("Rename") { renameFolder() }
                Button("Cancel", role: .cancel) { folderToRename = nil }
            }
            .confirmationDialog(
                "Delete \(folderToDelete?.name ?? "folder")?",
                isPresented: Binding(
                    get: { folderToDelete != nil },
                    set: { if !$0 { folderToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete folder", role: .destructive) { deleteFolder() }
                Button("Cancel", role: .cancel) { folderToDelete = nil }
            } message: {
                Text("Variables inside will be moved to No Folder.")
            }
        }
    }

    private func folderRow(_ folder: VariableFolder) -> some View {
        let count = variableCount(in: folder)
        return HStack {
            Label(folder.name, systemImage: "folder")
            Spacer()
            Text(String(count))
                .foregroundStyle(.secondary)
            Menu {
                Button {
                    folderToRename = folder
                    renamedFolderName = folder.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    folderToDelete = folder
                } label: {
                    Label("Delete folder", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func createFolder() {
        let name = newFolderName
        Task {
            do {
                try await store.createFolder(name: name)
                newFolderName = ""
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func variableCount(in folder: VariableFolder) -> Int {
        store.variables.reduce(into: 0) { count, variable in
            if variable.folderID == folder.id { count += 1 }
        }
    }

    private func renameFolder() {
        guard let folder = folderToRename else { return }
        let name = renamedFolderName
        folderToRename = nil
        Task {
            do {
                try await store.renameFolder(folder, name: name)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteFolder() {
        guard let folder = folderToDelete else { return }
        folderToDelete = nil
        Task {
            do {
                try await store.deleteFolder(folder)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct VariableRow: View {
    let variable: GlobalVariable
    let folderName: String?

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
                if let folderName {
                    Label(folderName, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
