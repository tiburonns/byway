import Foundation
import Observation

@MainActor
@Observable
final class VariableStore {
    private(set) var variables: [GlobalVariable] = []
    private(set) var changes: [VariableChange] = []
    private(set) var storageStatus: StorageStatus?
    var isLoading = false
    var errorMessage: String?

    let repository: VariableRepository

    init(repository: VariableRepository = .shared) {
        self.repository = repository
    }

    func refresh(query: String = "") async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let variables = repository.list(matching: query)
            async let changes = repository.history()
            async let status = repository.storageStatus()
            self.variables = try await variables
            self.changes = try await changes
            self.storageStatus = try await status
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(
        existingID: UUID?,
        key: String,
        value: VariableValue,
        tags: [String],
        notes: String,
        isFavorite: Bool,
        expiresAt: Date?
    ) async throws {
        var destinationKey = key
        if let existingID {
            let existing = try await repository.variable(id: existingID)
            if existing.key.localizedCaseInsensitiveCompare(key) != .orderedSame {
                destinationKey = try await repository.rename(id: existingID, to: key).key
            }
        }
        _ = try await repository.set(
            key: destinationKey,
            value: value,
            tags: tags,
            notes: notes,
            isFavorite: isFavorite,
            expiresAt: expiresAt
        )
        await refresh()
    }

    func delete(_ variable: GlobalVariable) async {
        do {
            try await repository.delete(key: variable.key)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFavorite(_ isFavorite: Bool, for variable: GlobalVariable) async {
        do {
            _ = try await repository.set(
                key: variable.key,
                value: variable.value,
                tags: variable.tags,
                notes: variable.notes,
                isFavorite: isFavorite,
                expiresAt: variable.expiresAt
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(_ change: VariableChange) async {
        do {
            _ = try await repository.restore(changeID: change.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportArchive() async throws -> Data {
        try await repository.exportArchive()
    }

    func importArchive(_ data: Data, strategy: ImportStrategy) async throws -> Int {
        let count = try await repository.importArchive(data: data, strategy: strategy)
        await refresh()
        return count
    }

    func removeExpired() async throws -> Int {
        let count = try await repository.removeExpired()
        await refresh()
        return count
    }
}
