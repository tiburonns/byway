import SwiftUI

struct HistoryView: View {
    @Environment(VariableStore.self) private var store

    var body: some View {
        Group {
            if store.changes.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Variable changes will appear here.")
                )
            } else {
                List(store.changes) { change in
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: change.operation))
                            .foregroundStyle(color(for: change.operation))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(change.key).font(.headline)
                            Text(title(for: change.operation))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(change.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await store.restore(change) }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .help("Restore this version")
                    }
                    .padding(.vertical, 3)
                }
                .refreshable { await store.refresh() }
            }
        }
        .navigationTitle("History")
    }

    private func symbol(for operation: ChangeOperation) -> String {
        switch operation {
        case .create: "plus.circle.fill"
        case .update: "pencil.circle.fill"
        case .delete: "trash.circle.fill"
        case .restore: "arrow.uturn.backward.circle.fill"
        case .importVariables: "square.and.arrow.down.fill"
        }
    }

    private func title(for operation: ChangeOperation) -> LocalizedStringKey {
        switch operation {
        case .create: "Created"
        case .update: "Updated"
        case .delete: "Deleted"
        case .restore: "Restored"
        case .importVariables: "Imported"
        }
    }

    private func color(for operation: ChangeOperation) -> Color {
        switch operation {
        case .create: .green
        case .update: .blue
        case .delete: .red
        case .restore: .orange
        case .importVariables: .purple
        }
    }
}
