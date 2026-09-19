import CryptoKit
import Foundation
import Security

actor VariableRepository {
    static let shared = VariableRepository()
    static let maximumArchiveBytes = 64 * 1_024 * 1_024
    static let maximumAttachmentBytes = 25 * 1_024 * 1_024
    static let maximumArchiveVariables = 2_000
    static let maximumArchiveAttachments = 1_000
    static let archiveEncryptionIterations = 100_000

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastStatus: StorageStatus?

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func storageStatus() throws -> StorageStatus {
        try prepareStorage().status
    }

    func snapshot(matching query: String = "", historyLimit: Int = 200) throws -> VariableRepositorySnapshot {
        let storage = try prepareStorage()
        return VariableRepositorySnapshot(
            variables: try readVariables(storage: storage, matching: query),
            folders: try readFolders(storage: storage),
            changes: try readHistory(storage: storage, limit: historyLimit),
            storageStatus: storage.status,
            quarantinedFileCount: try quarantinedFileCount(storage: storage)
        )
    }

    func list(
        matching query: String = "",
        includeExpired: Bool = false,
        tag: String? = nil
    ) throws -> [GlobalVariable] {
        let storage = try prepareStorage()
        return try readVariables(
            storage: storage,
            matching: query,
            includeExpired: includeExpired,
            tag: tag
        )
    }

    private func readVariables(
        storage: PreparedStorage,
        matching query: String = "",
        includeExpired: Bool = false,
        tag: String? = nil
    ) throws -> [GlobalVariable] {
        let urls = try fileManager.contentsOfDirectory(
            at: storage.variables,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var decodedVariables: [GlobalVariable] = []
        for url in urls where url.pathExtension == "json" {
            do {
                decodedVariables.append(try readVariable(at: url))
            } catch is DecodingError {
                try quarantineCorruptItem(
                    at: url,
                    storage: storage,
                    category: "variable"
                )
            }
        }

        return decodedVariables
            .filter { includeExpired || !$0.isExpired }
            .filter { variable in
                guard let tag else { return true }
                return variable.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
            .filter { variable in
                normalizedQuery.isEmpty
                    || variable.key.localizedCaseInsensitiveContains(normalizedQuery)
                    || variable.notes.localizedCaseInsensitiveContains(normalizedQuery)
                    || variable.tags.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
            }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
    }

    func variable(forKey key: String, includeExpired: Bool = false) throws -> GlobalVariable {
        let normalized = try normalizedKey(key)
        let storage = try prepareStorage()
        let url = variableURL(forNormalizedKey: normalized, storage: storage)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BywayError.notFound(key)
        }

        let variable = try readVariable(at: url)
        if variable.isExpired && !includeExpired {
            throw BywayError.notFound(key)
        }
        return variable
    }

    func variable(id: UUID) throws -> GlobalVariable {
        guard let result = try list(includeExpired: true).first(where: { $0.id == id }) else {
            throw BywayError.notFound(id.uuidString)
        }
        return result
    }

    func exists(key: String, includeExpired: Bool = false) throws -> Bool {
        do {
            _ = try variable(forKey: key, includeExpired: includeExpired)
            return true
        } catch BywayError.notFound {
            return false
        }
    }

    func listFolders() throws -> [VariableFolder] {
        let storage = try prepareStorage()
        return try readFolders(storage: storage)
    }

    private func readFolders(storage: PreparedStorage) throws -> [VariableFolder] {
        let urls = try fileManager.contentsOfDirectory(
            at: storage.folders,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var folders: [VariableFolder] = []

        for url in urls where url.pathExtension == "json" {
            do {
                let data = try coordinatedReadData(at: url)
                folders.append(
                    try decoder.decode(
                        VariableFolder.self,
                        from: data
                    )
                )
            } catch is DecodingError {
                try quarantineCorruptItem(
                    at: url,
                    storage: storage,
                    category: "folder"
                )
            }
        }

        return folders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func createFolder(name: String) throws -> VariableFolder {
        let cleanName = try normalizedFolderName(name)
        let folders = try listFolders()
        guard !folders.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) else {
            throw BywayError.invalidValue("A folder named \(cleanName) already exists.")
        }
        let folder = VariableFolder(name: cleanName)
        try write(folder, storage: try prepareStorage())
        return folder
    }

    @discardableResult
    func renameFolder(id: UUID, name: String) throws -> VariableFolder {
        let cleanName = try normalizedFolderName(name)
        let folders = try listFolders()
        guard var folder = folders.first(where: { $0.id == id }) else {
            throw BywayError.notFound(id.uuidString)
        }
        guard !folders.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) else {
            throw BywayError.invalidValue("A folder named \(cleanName) already exists.")
        }
        folder.name = cleanName
        folder.updatedAt = .now
        try write(folder, storage: try prepareStorage())
        return folder
    }

    func deleteFolder(id: UUID) throws {
        let storage = try prepareStorage()
        guard try listFolders().contains(where: { $0.id == id }) else {
            throw BywayError.notFound(id.uuidString)
        }
        let variables = try list(includeExpired: true).filter { $0.folderID == id }
        if !variables.isEmpty {
            _ = try applyTransaction(variables.map { .move(key: $0.key, folderID: nil) })
        }
        let url = folderURL(id: id, storage: storage)
        if fileManager.fileExists(atPath: url.path) {
            try coordinatedRemoveItem(at: url)
        }
    }

    @discardableResult
    func moveVariables(ids: Set<UUID>, to folderID: UUID?) throws -> Int {
        if let folderID, try !listFolders().contains(where: { $0.id == folderID }) {
            throw BywayError.notFound(folderID.uuidString)
        }
        let selected = try list(includeExpired: true).filter { ids.contains($0.id) }
        guard selected.count == ids.count else {
            throw BywayError.notFound("one or more selected variables")
        }
        let summary = try applyTransaction(selected.map { .move(key: $0.key, folderID: folderID) })
        return summary.updatedCount
    }

    @discardableResult
    func deleteVariables(ids: Set<UUID>) throws -> Int {
        let selected = try list(includeExpired: true).filter { ids.contains($0.id) }
        guard selected.count == ids.count else {
            throw BywayError.notFound("one or more selected variables")
        }
        return try applyTransaction(selected.map { .delete(key: $0.key) }).deletedCount
    }

    @discardableResult
    func set(
        key: String,
        value: VariableValue,
        tags: [String]? = nil,
        notes: String? = nil,
        isFavorite: Bool? = nil,
        expiresAt: Date? = nil
    ) throws -> GlobalVariable {
        let normalized = try normalizedKey(key)
        let storage = try prepareStorage()
        let url = variableURL(forNormalizedKey: normalized, storage: storage)
        let previousData: Data?
        if fileManager.fileExists(atPath: url.path) {
            try resolveVariableConflictsIfNeeded(at: url)
            previousData = try coordinatedReadData(at: url)
        } else {
            previousData = nil
        }
        let existing = try previousData.map { try decoder.decode(GlobalVariable.self, from: $0) }

        var variable = existing ?? GlobalVariable(key: key.trimmingCharacters(in: .whitespacesAndNewlines), value: value)
        variable.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        variable.value = value
        variable.updatedAt = .now
        variable.revision = (existing?.revision ?? 0) + 1
        if let tags { variable.tags = normalizedTags(tags) }
        if let notes { variable.notes = notes }
        if let isFavorite { variable.isFavorite = isFavorite }
        variable.expiresAt = expiresAt

        try write(variable, to: url)
        do {
            try recordChange(VariableChange(
                variableID: variable.id,
                key: variable.key,
                operation: existing == nil ? .create : .update,
                previous: existing,
                current: variable
            ), storage: storage)
            if fileReferenceIDs(in: existing?.value) != fileReferenceIDs(in: variable.value) {
                _ = try? removeOrphanedAttachments(storage: storage)
            }
        } catch {
            if let previousData {
                try? coordinatedWriteData(
                    previousData,
                    to: url
                )
            } else {
                try? coordinatedRemoveItem(at: url)
            }
            throw error
        }
        return variable
    }

    @discardableResult
    func rename(id: UUID, to newKey: String) throws -> GlobalVariable {
        var variable = try variable(id: id)
        let oldNormalized = try normalizedKey(variable.key)
        let newNormalized = try normalizedKey(newKey)
        let storage = try prepareStorage()
        let oldURL = variableURL(
            forNormalizedKey: oldNormalized,
            storage: storage
        )
        let newURL = variableURL(
            forNormalizedKey: newNormalized,
            storage: storage
        )

        if oldNormalized != newNormalized,
           fileManager.fileExists(atPath: newURL.path) {
            throw BywayError.duplicateKey(newKey)
        }

        let previous = variable
        let previousData = try coordinatedReadData(
            at: oldURL
        )

        variable.key = newKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        variable.updatedAt = .now
        variable.revision += 1

        try write(variable, to: newURL)

        do {
            if oldURL != newURL,
               fileManager.fileExists(
                atPath: oldURL.path
               ) {
                try coordinatedRemoveItem(
                    at: oldURL
                )
            }

            try recordChange(
                VariableChange(
                    variableID: variable.id,
                    key: variable.key,
                    operation: .update,
                    previous: previous,
                    current: variable
                ),
                storage: storage
            )
        } catch {
            // A rename and its history entry are one logical operation.
            // Restore the original variable if either removal or history
            // recording fails.
            try? coordinatedWriteData(
                previousData,
                to: oldURL
            )
            if oldURL != newURL {
                try? coordinatedRemoveItem(
                    at: newURL
                )
            }
            throw error
        }

        return variable
    }

    func delete(key: String) throws {
        let variable = try variable(forKey: key, includeExpired: true)
        let storage = try prepareStorage()
        let url = variableURL(forNormalizedKey: try normalizedKey(key), storage: storage)
        try resolveVariableConflictsIfNeeded(at: url)
        let originalData = try coordinatedReadData(at: url)
        try coordinatedRemoveItem(at: url)
        do {
            try recordChange(VariableChange(
                variableID: variable.id,
                key: variable.key,
                operation: .delete,
                previous: variable,
                current: nil
            ), storage: storage)
            if !fileReferences(in: variable.value).isEmpty {
                _ = try? removeOrphanedAttachments(storage: storage)
            }
        } catch {
            try? coordinatedWriteData(
                originalData,
                to: url
            )
            throw error
        }
    }

    @discardableResult
    func toggle(key: String) throws -> Bool {
        let variable = try variable(forKey: key)
        guard case .boolean(let value) = variable.value else {
            throw BywayError.typeMismatch(expected: .boolean, actual: variable.value.kind)
        }
        let result = !value
        try set(key: variable.key, value: .boolean(result), expiresAt: variable.expiresAt)
        return result
    }

    @discardableResult
    func increment(key: String, by amount: Double) throws -> Double {
        let variable = try variable(forKey: key)
        switch variable.value {
        case .integer(let value):
            if amount.rounded(.towardZero) == amount,
               let decimal = Decimal(string: String(amount)),
               decimal >= Decimal(Int64.min), decimal <= Decimal(Int64.max) {
                let delta = NSDecimalNumber(decimal: decimal).int64Value
                let (result, overflow) = value.addingReportingOverflow(delta)
                guard !overflow else {
                    throw BywayError.invalidValue("The increment would exceed the 64-bit integer range.")
                }
                try set(key: variable.key, value: .integer(result), expiresAt: variable.expiresAt)
                return Double(result)
            }
            let result = Double(value) + amount
            guard result.isFinite else {
                throw BywayError.invalidValue("The increment produced a non-finite number.")
            }
            try set(key: variable.key, value: .number(result), expiresAt: variable.expiresAt)
            return result
        case .number(let value):
            let result = value + amount
            guard result.isFinite else {
                throw BywayError.invalidValue("The increment produced a non-finite number.")
            }
            try set(key: variable.key, value: .number(result), expiresAt: variable.expiresAt)
            return result
        default:
            throw BywayError.typeMismatch(expected: .number, actual: variable.value.kind)
        }
    }

    @discardableResult
    func append(key: String, values: [VariableValue]) throws -> [VariableValue] {
        let variable = try variable(forKey: key)
        guard case .array(let existing) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        let result = existing + values
        try set(key: variable.key, value: .array(result), expiresAt: variable.expiresAt)
        return result
    }

    @discardableResult
    func ensure(key: String, value: VariableValue, expiresAt: Date? = nil) throws -> (variable: GlobalVariable, created: Bool) {
        if try exists(key: key, includeExpired: true) {
            let existing = try variable(forKey: key, includeExpired: true)
            return (existing, false)
        }
        let summary = try applyTransaction([.ensure(key: key, value: value, expiresAt: expiresAt)])
        return (try variable(forKey: key, includeExpired: true), summary.createdCount == 1)
    }

    func dictionaryEntry(key: String, path: String) throws -> VariableValue? {
        let variable = try variable(forKey: key)
        guard case .dictionary = variable.value else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: variable.value.kind)
        }
        return try variable.value.value(atPath: path)
    }

    @discardableResult
    func setDictionaryEntry(key: String, field: String, value: VariableValue) throws -> [String: VariableValue] {
        let variable = try variable(forKey: key)
        guard case .dictionary = variable.value else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: variable.value.kind)
        }
        let updated = try variable.value.settingValue(value, atPath: field)
        guard case .dictionary(let dictionary) = updated else {
            throw BywayError.invalidValue("Invalid dictionary result.")
        }
        try set(key: variable.key, value: updated, expiresAt: variable.expiresAt)
        return dictionary
    }

    @discardableResult
    func removeDictionaryEntry(key: String, field: String) throws -> [String: VariableValue] {
        let variable = try variable(forKey: key)
        guard case .dictionary = variable.value else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: variable.value.kind)
        }
        let result = try variable.value.removingValue(atPath: field)
        guard case .dictionary(let dictionary) = result.value else {
            throw BywayError.invalidValue("Invalid dictionary result.")
        }
        try set(key: variable.key, value: result.value, expiresAt: variable.expiresAt)
        return dictionary
    }

    func listCount(key: String) throws -> Int {
        let variable = try variable(forKey: key)
        guard case .array(let values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        return values.count
    }

    func findListItems(
        key: String,
        path: String? = nil,
        equalTo expected: VariableValue? = nil,
        limit: Int = 100
    ) throws -> [(index: Int, value: VariableValue)] {
        let variable = try variable(forKey: key)
        guard case .array(let values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        let maximum = min(max(limit, 0), 1_000)
        return try values.enumerated().compactMap { index, value in
            let candidate = try path.map { try value.value(atPath: $0) } ?? value
            guard let candidate else { return nil }
            guard expected.map({ candidate == $0 }) ?? true else { return nil }
            return (index, value)
        }.prefix(maximum).map { $0 }
    }

    @discardableResult
    func updateListItem(key: String, index: Int, value: VariableValue) throws -> [VariableValue] {
        let variable = try variable(forKey: key)
        guard case .array(var values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        guard values.indices.contains(index) else {
            throw BywayError.invalidValue("List index \(index) is out of bounds.")
        }
        values[index] = value
        try set(key: variable.key, value: .array(values), expiresAt: variable.expiresAt)
        return values
    }

    @discardableResult
    func deleteListItem(key: String, index: Int) throws -> [VariableValue] {
        let variable = try variable(forKey: key)
        guard case .array(var values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        guard values.indices.contains(index) else {
            throw BywayError.invalidValue("List index \(index) is out of bounds.")
        }
        values.remove(at: index)
        try set(key: variable.key, value: .array(values), expiresAt: variable.expiresAt)
        return values
    }

    @discardableResult
    func sortList(key: String, path: String? = nil, ascending: Bool = true) throws -> [VariableValue] {
        let variable = try variable(forKey: key)
        guard case .array(let values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        let decorated = try values.enumerated().map { index, value in
            (index: index, value: value, sortValue: try path.map { try value.value(atPath: $0) } ?? value)
        }
        let sorted = decorated.sorted { left, right in
            guard let lhs = left.sortValue else { return false }
            guard let rhs = right.sortValue else { return true }
            let comparison = compareForSorting(lhs, rhs)
            if comparison == .orderedSame { return left.index < right.index }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }.map(\.value)
        try set(key: variable.key, value: .array(sorted), expiresAt: variable.expiresAt)
        return sorted
    }

    @discardableResult
    func removeDuplicateListItems(key: String) throws -> [VariableValue] {
        let variable = try variable(forKey: key)
        guard case .array(let values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        var seen = Set<VariableValue>()
        let unique = values.filter { seen.insert($0).inserted }
        try set(key: variable.key, value: .array(unique), expiresAt: variable.expiresAt)
        return unique
    }

    @discardableResult
    func appendEvent(key: String = "HISTORY.Events", event: BywayEvent) throws -> BywayEvent {
        _ = try applyTransaction([
            .ensure(key: key, value: .array([]), expiresAt: nil),
            .append(key: key, values: [event.variableValue])
        ])
        return event
    }

    func queryEvents(
        key: String = "HISTORY.Events",
        category: String? = nil,
        action: String? = nil,
        from startDate: Date? = nil,
        through endDate: Date? = nil,
        limit: Int = 100,
        newestFirst: Bool = true
    ) throws -> [BywayEvent] {
        let variable = try variable(forKey: key)
        guard case .array(let values) = variable.value else {
            throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
        }
        let normalizedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAction = action?.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximum = min(max(limit, 0), 1_000)
        return values.compactMap { try? BywayEvent(variableValue: $0) }
            .filter { event in
                (normalizedCategory.map { $0.isEmpty || event.category.localizedCaseInsensitiveCompare($0) == .orderedSame } ?? true)
                    && (normalizedAction.map { $0.isEmpty || event.action.localizedCaseInsensitiveCompare($0) == .orderedSame } ?? true)
                    && (startDate.map { event.timestamp >= $0 } ?? true)
                    && (endDate.map { event.timestamp <= $0 } ?? true)
            }
            .sorted { newestFirst ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp }
            .prefix(maximum)
            .map { $0 }
    }

    func lastEvent(key: String = "HISTORY.Events", category: String? = nil, action: String? = nil) throws -> BywayEvent {
        guard let event = try queryEvents(key: key, category: category, action: action, limit: 1).first else {
            throw BywayError.notFound("matching event in \(key)")
        }
        return event
    }

    @discardableResult
    func applyTransaction(_ mutations: [VariableMutation]) throws -> TransactionSummary {
        guard !mutations.isEmpty else {
            return TransactionSummary(affectedKeys: [], createdCount: 0, updatedCount: 0, deletedCount: 0, skippedCount: 0)
        }
        let storage = try prepareStorage()
        var entries: [String: TransactionEntry] = [:]
        var skippedCount = 0

        for mutation in mutations {
            let normalized = try normalizedKey(mutation.key)
            if entries[normalized] == nil {
                let url = variableURL(forNormalizedKey: normalized, storage: storage)
                let existing: GlobalVariable?
                if fileManager.fileExists(atPath: url.path) {
                    existing = try readVariable(at: url)
                } else {
                    existing = nil
                }
                entries[normalized] = TransactionEntry(normalizedKey: normalized, original: existing, current: existing)
            }
            guard var entry = entries[normalized] else { continue }

            switch mutation {
            case .set(let key, let value, let expiresAt):
                entry.current = updatedVariable(existing: entry.current, key: key, value: value, expiresAt: expiresAt)
            case .ensure(let key, let value, let expiresAt):
                if entry.current == nil {
                    entry.current = updatedVariable(existing: nil, key: key, value: value, expiresAt: expiresAt)
                } else {
                    skippedCount += 1
                }
            case .replace(let variable):
                entry.current = variable
            case .delete:
                if entry.current == nil { skippedCount += 1 }
                entry.current = nil
            case .append(_, let values):
                guard var variable = entry.current else { throw BywayError.notFound(mutation.key) }
                guard case .array(let existing) = variable.value else {
                    throw BywayError.typeMismatch(expected: .array, actual: variable.value.kind)
                }
                variable.value = .array(existing + values)
                variable.updatedAt = .now
                variable.revision += 1
                entry.current = variable
            case .setDictionaryEntry(_, let path, let value):
                guard var variable = entry.current else { throw BywayError.notFound(mutation.key) }
                variable.value = try variable.value.settingValue(value, atPath: path)
                variable.updatedAt = .now
                variable.revision += 1
                entry.current = variable
            case .removeDictionaryEntry(_, let path):
                guard var variable = entry.current else { throw BywayError.notFound(mutation.key) }
                variable.value = try variable.value.removingValue(atPath: path).value
                variable.updatedAt = .now
                variable.revision += 1
                entry.current = variable
            case .move(_, let folderID):
                guard var variable = entry.current else { throw BywayError.notFound(mutation.key) }
                variable.folderID = folderID
                variable.updatedAt = .now
                variable.revision += 1
                entry.current = variable
            }
            entries[normalized] = entry
        }

        let changed = entries.values.filter { $0.original != $0.current }
        guard !changed.isEmpty else {
            return TransactionSummary(affectedKeys: [], createdCount: 0, updatedCount: 0, deletedCount: 0, skippedCount: skippedCount)
        }

        let changes = changed.map { entry in
            VariableChange(
                variableID: entry.current?.id ?? entry.original!.id,
                key: entry.current?.key ?? entry.original!.key,
                operation: entry.original == nil ? .create : (entry.current == nil ? .delete : .update),
                previous: entry.original,
                current: entry.current
            )
        }
        let transactionURL = try beginTransaction(entries: changed, changes: changes, storage: storage)
        do {
            for entry in changed {
                let url = variableURL(forNormalizedKey: entry.normalizedKey, storage: storage)
                if let variable = entry.current {
                    try write(variable, to: url)
                } else if fileManager.fileExists(atPath: url.path) {
                    try coordinatedRemoveItem(at: url)
                }
            }
            for change in changes {
                let url = storage.history.appendingPathComponent("\(change.id.uuidString).json")
                try encoder.encode(change).write(to: url, options: [.atomic])
            }
            try pruneHistory(storage: storage)
            try fileManager.removeItem(at: transactionURL)
            if changed.contains(where: {
                fileReferenceIDs(in: $0.original?.value) != fileReferenceIDs(in: $0.current?.value)
            }) {
                _ = try? removeOrphanedAttachments(storage: storage)
            }
        } catch {
            try? rollbackTransaction(at: transactionURL, storage: storage)
            throw error
        }

        return TransactionSummary(
            affectedKeys: changed.map { $0.current?.key ?? $0.original!.key }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            createdCount: changed.filter { $0.original == nil && $0.current != nil }.count,
            updatedCount: changed.filter { $0.original != nil && $0.current != nil }.count,
            deletedCount: changed.filter { $0.original != nil && $0.current == nil }.count,
            skippedCount: skippedCount
        )
    }

    func saveFile(data: Data, filename: String, contentType: String) throws -> StoredFile {
        guard data.count <= Self.maximumAttachmentBytes else {
            throw BywayError.invalidValue("A stored file cannot exceed 25 MB.")
        }
        guard !filename.isEmpty, filename.count <= 255, contentType.count <= 255 else {
            throw BywayError.invalidValue("The file name or content type is invalid.")
        }
        let storage = try prepareStorage()
        let file = StoredFile(filename: filename, contentType: contentType, byteCount: data.count)
        let url = attachmentURL(for: file, storage: storage)
        try coordinatedWriteData(data, to: url)
        return file
    }

    @discardableResult
    func setFile(
        key: String,
        data: Data,
        filename: String,
        contentType: String,
        expiresAt: Date? = nil
    ) throws -> GlobalVariable {
        let file = try saveFile(data: data, filename: filename, contentType: contentType)
        do {
            return try set(key: key, value: .file(file), expiresAt: expiresAt)
        } catch {
            let storage = try? prepareStorage()
            if let storage {
                try? coordinatedRemoveItem(
                    at: attachmentURL(
                        for: file,
                        storage: storage
                    )
                )
            }
            throw error
        }
    }

    func fileData(for file: StoredFile) throws -> Data {
        let storage = try prepareStorage()
        let url = attachmentURL(for: file, storage: storage)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BywayError.missingFile(file.filename)
        }
        return try coordinatedReadData(at: url)
    }

    func history(limit: Int = 200) throws -> [VariableChange] {
        let storage = try prepareStorage()
        return try readHistory(storage: storage, limit: limit)
    }

    private func readHistory(storage: PreparedStorage, limit: Int = 200) throws -> [VariableChange] {
        let urls = try fileManager.contentsOfDirectory(
            at: storage.history,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
            guard let data = try? coordinatedReadData(at: url) else {
                return nil
            }
            return try? decoder.decode(
                VariableChange.self,
                from: data
            )
        }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(0, limit))
            .map { $0 }
    }

    @discardableResult
    func restore(changeID: UUID) throws -> GlobalVariable {
        let storage = try prepareStorage()
        let changeURL = storage.history.appendingPathComponent("\(changeID.uuidString).json")
        let change = try decoder.decode(
            VariableChange.self,
            from: coordinatedReadData(at: changeURL)
        )
        guard var snapshot = change.previous ?? change.current else {
            throw BywayError.invalidValue("This history item has no restorable snapshot.")
        }

        // Refuse to restore a dangling file reference. The current state must
        // remain unchanged if a historical attachment is unavailable.
        for file in fileReferences(
            in: snapshot.value
        ) {
            _ = try fileData(for: file)
        }

        snapshot.updatedAt = .now
        snapshot.revision += 1
        let url = variableURL(forNormalizedKey: try normalizedKey(snapshot.key), storage: storage)
        let existing = try? readVariable(at: url)
        try write(snapshot, to: url)
        try recordChange(
            VariableChange(
                variableID: snapshot.id,
                key: snapshot.key,
                operation: .restore,
                previous: existing,
                current: snapshot
            ),
            storage: storage
        )
        return snapshot
    }

    func removeExpired() throws -> Int {
        let expired = try list(includeExpired: true).filter(\.isExpired)
        for variable in expired {
            try delete(key: variable.key)
        }
        return expired.count
    }

    func exportArchive(variableIDs: Set<UUID>? = nil, variableKeys: Set<String>? = nil) throws -> Data {
        let normalizedKeys = try variableKeys.map { keys in
            Set(try keys.map(normalizedKey))
        }
        let variables = try list(includeExpired: true).filter { variable in
            (variableIDs.map { $0.contains(variable.id) } ?? true)
                && (normalizedKeys.map { $0.contains((try? normalizedKey(variable.key)) ?? "") } ?? true)
        }
        if let normalizedKeys {
            let exportedKeys = Set(try variables.map { try normalizedKey($0.key) })
            if let missing = normalizedKeys.subtracting(exportedKeys).first {
                let requested = variableKeys?.first(where: { (try? normalizedKey($0)) == missing }) ?? missing
                throw BywayError.notFound(requested)
            }
        }
        var attachments: [String: Data] = [:]
        for file in variables.flatMap({ fileReferences(in: $0.value) }) {
            attachments[file.id.uuidString] = try fileData(for: file)
        }
        let allFolders = try listFolders()
        let folders: [VariableFolder]
        if variableIDs == nil && variableKeys == nil {
            folders = allFolders
        } else {
            let folderIDs = Set(variables.compactMap(\.folderID))
            folders = allFolders.filter { folderIDs.contains($0.id) }
        }
        let archive = BywayArchive(variables: variables, attachments: attachments, folders: folders)
        return try encoder.encode(archive)
    }

    func exportEncryptedArchive(
        variableIDs: Set<UUID>? = nil,
        variableKeys: Set<String>? = nil,
        passphrase: String
    ) throws -> Data {
        let cleanPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPassphrase.count >= 8 else {
            throw BywayError.invalidValue("Use a passphrase with at least 8 characters.")
        }
        let archiveData = try exportArchive(variableIDs: variableIDs, variableKeys: variableKeys)
        let salt = try secureRandomData(count: 16)
        let key = pbkdf2ArchiveEncryptionKey(
            passphrase: cleanPassphrase,
            salt: salt,
            iterations: Self.archiveEncryptionIterations
        )
        let sealed = try ChaChaPoly.seal(archiveData, using: key)
        let envelope = BywayEncryptedArchive(
            salt: salt,
            iterations: Self.archiveEncryptionIterations,
            sealedArchive: sealed.combined
        )
        return try encoder.encode(envelope)
    }

    func previewArchive(data: Data, strategy: ImportStrategy, passphrase: String? = nil) throws -> ArchivePreview {
        let decoded = try decodedArchive(data: data, passphrase: passphrase)
        let plan = try importPlan(for: decoded.archive, strategy: strategy)
        return ArchivePreview(
            archiveVersion: decoded.archive.version,
            totalVariables: decoded.archive.variables.count,
            variablesToImport: plan.variablesToImport.count,
            skippedExisting: plan.skippedExisting,
            overwrittenExisting: plan.overwrittenExisting,
            removedExisting: plan.removedExisting,
            attachments: decoded.archive.attachments.count,
            folders: decoded.archive.folders.count,
            attachmentBytes: decoded.archive.attachments.values.reduce(0) { $0 + $1.count },
            isEncrypted: decoded.isEncrypted
        )
    }

    @discardableResult
    func importArchive(data: Data, strategy: ImportStrategy, passphrase: String? = nil) throws -> Int {
        let decoded = try decodedArchive(data: data, passphrase: passphrase)
        let archive = decoded.archive
        let plan = try importPlan(for: archive, strategy: strategy)
        let storage = try prepareStorage()

        let importBackup = fileManager.temporaryDirectory
            .appendingPathComponent("byway-import-\(UUID().uuidString)", isDirectory: true)
        try backupProtectedDirectories(storage: storage, to: importBackup)
        do {
            for variable in plan.variablesToImport {
                for file in fileReferences(in: variable.value) {
                    guard let attachment = archive.attachments[file.id.uuidString] else { continue }
                    let target = attachmentURL(for: file, storage: storage)
                    try coordinatedWriteData(
                        attachment,
                        to: target
                    )
                }
            }
            _ = try applyTransaction(plan.mutations)
            for folder in archive.folders {
                try write(folder, storage: storage)
            }
            if strategy == .replaceAll {
                let retainedIDs = Set(archive.folders.map(\.id))
                for folder in try listFolders() where !retainedIDs.contains(folder.id) {
                    let url = folderURL(id: folder.id, storage: storage)
                    try coordinatedRemoveItem(at: url)
                }
            }
            _ = try? removeOrphanedAttachments(storage: storage)
            try preserveImportUndoBackup(importBackup, storage: storage)
        } catch {
            try? restoreProtectedDirectories(storage: storage, from: importBackup)
            try? fileManager.removeItem(at: importBackup)
            throw error
        }
        return plan.variablesToImport.count
    }

    func canUndoLastImport() throws -> Bool {
        let storage = try prepareStorage()
        return fileManager.fileExists(atPath: importUndoBackupURL(storage: storage).path)
    }

    func undoLastImport() throws {
        let storage = try prepareStorage()
        let undoBackup = importUndoBackupURL(storage: storage)
        guard fileManager.fileExists(atPath: undoBackup.path) else {
            throw BywayError.invalidValue("There is no imported archive to undo.")
        }
        let currentBackup = fileManager.temporaryDirectory
            .appendingPathComponent("byway-undo-\(UUID().uuidString)", isDirectory: true)
        try backupProtectedDirectories(storage: storage, to: currentBackup)
        do {
            try restoreProtectedDirectories(storage: storage, from: undoBackup)
            try fileManager.removeItem(at: undoBackup)
            try fileManager.moveItem(at: currentBackup, to: undoBackup)
        } catch {
            try? restoreProtectedDirectories(storage: storage, from: currentBackup)
            try? fileManager.removeItem(at: currentBackup)
            throw error
        }
    }

    private struct ImportPlan {
        var variablesToImport: [GlobalVariable]
        var mutations: [VariableMutation]
        var skippedExisting: Int
        var overwrittenExisting: Int
        var removedExisting: Int
    }

    private func decodedArchive(data: Data, passphrase: String?) throws -> (archive: BywayArchive, isEncrypted: Bool) {
        guard data.count <= Self.maximumArchiveBytes + 4_096 else {
            throw BywayError.invalidValue("A byway archive cannot exceed 64 MB.")
        }
        if let envelope = try? decoder.decode(BywayEncryptedArchive.self, from: data),
           envelope.format == BywayEncryptedArchive.format {
            guard envelope.version <= BywayEncryptedArchive.currentVersion else {
                throw BywayError.invalidValue("This encrypted archive was created by a newer version of byway.")
            }
            guard let passphrase, !passphrase.isEmpty else {
                throw BywayError.invalidValue("Enter the passphrase for this encrypted archive.")
            }
            guard envelope.iterations >= 10_000, envelope.iterations <= 1_000_000 else {
                throw BywayError.invalidValue("The encrypted archive uses unsupported security parameters.")
            }
            let key: SymmetricKey
            if envelope.version == 1 {
                key = legacyArchiveEncryptionKey(
                    passphrase: passphrase,
                    salt: envelope.salt,
                    iterations: envelope.iterations
                )
            } else {
                guard envelope.kdf == BywayEncryptedArchive.pbkdf2SHA256 else {
                    throw BywayError.invalidValue("The encrypted archive uses an unsupported key derivation function.")
                }
                key = pbkdf2ArchiveEncryptionKey(
                    passphrase: passphrase,
                    salt: envelope.salt,
                    iterations: envelope.iterations
                )
            }
            do {
                let sealedBox = try ChaChaPoly.SealedBox(combined: envelope.sealedArchive)
                let plaintext = try ChaChaPoly.open(sealedBox, using: key)
                return (try validatedArchive(data: plaintext), true)
            } catch {
                throw BywayError.invalidValue("The archive could not be decrypted. Check the passphrase.")
            }
        }
        return (try validatedArchive(data: data), false)
    }

    private func validatedArchive(data: Data) throws -> BywayArchive {
        guard data.count <= Self.maximumArchiveBytes else {
            throw BywayError.invalidValue("A byway archive cannot exceed 64 MB.")
        }
        let archive = try decoder.decode(BywayArchive.self, from: data)
        guard archive.version <= BywayArchive.currentVersion else {
            throw BywayError.invalidValue("This archive was created by a newer version of byway.")
        }
        guard archive.variables.count <= Self.maximumArchiveVariables,
              archive.attachments.count <= Self.maximumArchiveAttachments,
              archive.attachments.values.allSatisfy({ $0.count <= Self.maximumAttachmentBytes }) else {
            throw BywayError.invalidValue("The archive exceeds the supported variable, attachment, or file-size limits.")
        }

        let archiveFolderIDs = Set(archive.folders.map(\.id))
        guard archiveFolderIDs.count == archive.folders.count else {
            throw BywayError.invalidValue("The archive contains duplicate folder IDs.")
        }
        let normalizedFolderNames = archive.folders.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard !normalizedFolderNames.contains(""), Set(normalizedFolderNames).count == normalizedFolderNames.count else {
            throw BywayError.invalidValue("The archive contains invalid or duplicate folder names.")
        }
        var seenKeys = Set<String>()
        for variable in archive.variables {
            let normalized = try normalizedKey(variable.key)
            guard seenKeys.insert(normalized).inserted else {
                throw BywayError.invalidValue("The archive contains duplicate key \(variable.key).")
            }
            for file in fileReferences(in: variable.value) where archive.attachments[file.id.uuidString] == nil {
                throw BywayError.missingFile(file.filename)
            }
            if let folderID = variable.folderID, !archiveFolderIDs.contains(folderID) {
                throw BywayError.invalidValue("Variable \(variable.key) references a missing folder.")
            }
        }

        return archive
    }

    private func importPlan(for archive: BywayArchive, strategy: ImportStrategy) throws -> ImportPlan {
        let existingVariables = try list(includeExpired: true)
        let existingKeys = Set(try existingVariables.map { try normalizedKey($0.key) })
        var mutations: [VariableMutation] = strategy == .replaceAll
            ? existingVariables.map { .delete(key: $0.key) }
            : []
        var variablesToImport: [GlobalVariable] = []
        var skippedExisting = 0
        var overwrittenExisting = 0
        for variable in archive.variables {
            let normalized = try normalizedKey(variable.key)
            if strategy == .keepExisting && existingKeys.contains(normalized) {
                skippedExisting += 1
                continue
            }
            if existingKeys.contains(normalized) { overwrittenExisting += 1 }
            variablesToImport.append(variable)
            mutations.append(.replace(variable))
        }
        let removedExisting = strategy == .replaceAll
            ? existingVariables.filter { existing in
                !archive.variables.contains { (try? normalizedKey($0.key)) == (try? normalizedKey(existing.key)) }
            }.count
            : 0
        return ImportPlan(
            variablesToImport: variablesToImport,
            mutations: mutations,
            skippedExisting: skippedExisting,
            overwrittenExisting: overwrittenExisting,
            removedExisting: removedExisting
        )
    }

    private func secureRandomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BywayError.invalidValue("Could not generate secure random data for the encrypted archive.")
        }
        return Data(bytes)
    }

    private func pbkdf2ArchiveEncryptionKey(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) -> SymmetricKey {
        BywayArchiveCrypto.pbkdf2SHA256Key(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        )
    }

    private func legacyArchiveEncryptionKey(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) -> SymmetricKey {
        BywayArchiveCrypto.legacyKey(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        )
    }

    private func protectedDirectories(in storage: PreparedStorage) -> [URL] {
        [storage.variables, storage.attachments, storage.folders, storage.history]
    }

    private func backupProtectedDirectories(storage: PreparedStorage, to backup: URL) throws {
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        for directory in protectedDirectories(in: storage) {
            try fileManager.copyItem(
                at: directory,
                to: backup.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
            )
        }
    }

    private func restoreProtectedDirectories(storage: PreparedStorage, from backup: URL) throws {
        for directory in protectedDirectories(in: storage) {
            let source = backup.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else {
                throw BywayError.invalidValue("The import recovery backup is incomplete.")
            }
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.copyItem(at: source, to: directory)
        }
    }

    private func importUndoBackupURL(storage: PreparedStorage) -> URL {
        storage.status.rootURL
            .appendingPathComponent("ImportUndo", isDirectory: true)
            .appendingPathComponent("Latest", isDirectory: true)
    }

    private func preserveImportUndoBackup(_ temporaryBackup: URL, storage: PreparedStorage) throws {
        let undoBackup = importUndoBackupURL(storage: storage)
        let container = undoBackup.deletingLastPathComponent()
        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: undoBackup.path) {
            try fileManager.removeItem(at: undoBackup)
        }
        try fileManager.moveItem(at: temporaryBackup, to: undoBackup)
    }

    @discardableResult
    func removeOrphanedAttachments() throws -> Int {
        try removeOrphanedAttachments(storage: prepareStorage())
    }

    private func removeOrphanedAttachments(storage: PreparedStorage) throws -> Int {
        let variables = try readVariables(
            storage: storage,
            includeExpired: true
        )
        var referencedIDs = Set(
            variables.flatMap {
                fileReferences(in: $0.value).map(\.id)
            }
        )

        let historyURLs = try fileManager.contentsOfDirectory(
            at: storage.history,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            $0.pathExtension == "json"
        }

        // History is part of Byway's restore contract. An attachment referenced
        // by retained history is not orphaned even if the current variable no
        // longer points to it.
        for url in historyURLs {
            let data = try coordinatedReadData(at: url)
            let change = try decoder.decode(
                VariableChange.self,
                from: data
            )
            referencedIDs.formUnion(
                fileReferenceIDs(
                    in: change.previous?.value
                )
            )
            referencedIDs.formUnion(
                fileReferenceIDs(
                    in: change.current?.value
                )
            )
        }

        var removed = 0
        let attachmentURLs = try fileManager.contentsOfDirectory(
            at: storage.attachments,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in attachmentURLs {
            let identifier =
                url.deletingPathExtension()
                    .lastPathComponent
            guard let id = UUID(
                uuidString: identifier
            ),
            !referencedIDs.contains(id)
            else {
                continue
            }

            try coordinatedRemoveItem(at: url)
            removed += 1
        }

        return removed
    }

    private struct PreparedStorage {
        var status: StorageStatus
        var variables: URL
        var attachments: URL
        var folders: URL
        var history: URL
        var transactions: URL
        var quarantine: URL
    }

    private struct TransactionEntry {
        var normalizedKey: String
        var original: GlobalVariable?
        var current: GlobalVariable?
    }

    private struct TransactionJournal: Codable {
        var variableFilenames: [String]
        var historyFilenames: [String]
    }

    private func prepareStorage() throws -> PreparedStorage {
        let status = try BywayStorage.preferredRoot()
        try fileManager.createDirectory(at: status.rootURL, withIntermediateDirectories: true)

        let variables = status.rootURL.appendingPathComponent("Variables", isDirectory: true)
        let attachments = status.rootURL.appendingPathComponent("Attachments", isDirectory: true)
        let folders = status.rootURL.appendingPathComponent("Folders", isDirectory: true)
        let history = status.rootURL.appendingPathComponent("History", isDirectory: true)
        let transactions = status.rootURL.appendingPathComponent("Transactions", isDirectory: true)
        let quarantine = status.rootURL.appendingPathComponent("Quarantine", isDirectory: true)
        for directory in [variables, attachments, folders, history, transactions, quarantine] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if status.location == .iCloud, lastStatus?.location != .iCloud {
            try migrateLocalData(to: status.rootURL)
        }
        lastStatus = status
        let storage = PreparedStorage(
            status: status,
            variables: variables,
            attachments: attachments,
            folders: folders,
            history: history,
            transactions: transactions,
            quarantine: quarantine
        )
        try recoverTransactions(storage: storage)
        return storage
    }

    private func migrateLocalData(to destination: URL) throws {
        let local = try BywayStorage.localRoot()
        guard local != destination, fileManager.fileExists(atPath: local.path) else { return }
        for directoryName in ["Variables", "Attachments", "Folders", "History", "Quarantine"] {
            let sourceDirectory = local.appendingPathComponent(directoryName, isDirectory: true)
            let destinationDirectory = destination.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for source in files {
                let target = destinationDirectory.appendingPathComponent(source.lastPathComponent)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                try? fileManager.copyItem(at: source, to: target)
            }
        }
    }

    private func quarantinedFileCount(storage: PreparedStorage) throws -> Int {
        try fileManager.contentsOfDirectory(
            at: storage.quarantine,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { !$0.hasDirectoryPath }.count
    }

    private func quarantineCorruptItem(
        at url: URL,
        storage: PreparedStorage,
        category: String
    ) throws {
        let data = try coordinatedReadData(at: url)
        let timestamp = Int(Date().timeIntervalSince1970)
        let destination = storage.quarantine
            .appendingPathComponent(
                "\(category)-\(timestamp)-\(UUID().uuidString)-\(url.lastPathComponent)"
            )

        // Preserve the original bytes before removing the active copy. If the
        // quarantine write fails, the source file is left untouched.
        try coordinatedWriteData(data, to: destination)
        try coordinatedRemoveItem(at: url)
    }

    private func readVariable(at url: URL) throws -> GlobalVariable {
        try resolveVariableConflictsIfNeeded(at: url)
        return try decoder.decode(
            GlobalVariable.self,
            from: coordinatedReadData(at: url)
        )
    }

    private func write(_ variable: GlobalVariable, to url: URL) throws {
        try coordinatedWriteData(encoder.encode(variable), to: url)
    }

    private func write(_ folder: VariableFolder, storage: PreparedStorage) throws {
        try coordinatedWriteData(
            encoder.encode(folder),
            to: folderURL(id: folder.id, storage: storage)
        )
    }

    private func recordChange(_ change: VariableChange, storage: PreparedStorage) throws {
        let url = storage.history.appendingPathComponent("\(change.id.uuidString).json")
        try coordinatedWriteData(encoder.encode(change), to: url)
        try pruneHistory(storage: storage)
    }

    private func coordinatedReadData(at url: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Data, Error>?

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try Data(contentsOf: coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw BywayError.storageUnavailable
        }
        return try result.get()
    }

    private func coordinatedWriteData(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(
            writingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private func coordinatedRemoveItem(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var removeError: Error?

        coordinator.coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.removeItem(at: coordinatedURL)
            } catch {
                removeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let removeError {
            throw removeError
        }
    }

    private func resolveVariableConflictsIfNeeded(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path),
              let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else {
            return
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var resolutionError: Error?

        coordinator.coordinate(
            writingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                var candidates: [(variable: GlobalVariable, data: Data)] = []

                if let currentData = try? Data(contentsOf: coordinatedURL),
                   let current = try? decoder.decode(GlobalVariable.self, from: currentData) {
                    candidates.append((current, currentData))
                }

                for version in conflicts {
                    guard let data = try? Data(contentsOf: version.url),
                          let variable = try? decoder.decode(GlobalVariable.self, from: data) else {
                        continue
                    }
                    candidates.append((variable, data))
                }

                let variables = candidates.map(\.variable)
                guard let winnerIndex = VariableConflictResolver.preferredIndex(
                    in: variables
                ) else {
                    throw BywayError.invalidValue(
                        "An iCloud conflict could not be decoded safely."
                    )
                }

                try candidates[winnerIndex].data.write(
                    to: coordinatedURL,
                    options: [.atomic]
                )

                for version in conflicts {
                    version.isResolved = true
                    try? version.remove()
                }
            } catch {
                resolutionError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let resolutionError {
            throw resolutionError
        }
    }

    private func updatedVariable(
        existing: GlobalVariable?,
        key: String,
        value: VariableValue,
        expiresAt: Date?
    ) -> GlobalVariable {
        var variable = existing ?? GlobalVariable(
            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
            value: value
        )
        variable.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        variable.value = value
        variable.updatedAt = .now
        variable.expiresAt = expiresAt
        variable.revision = (existing?.revision ?? 0) + 1
        return variable
    }

    private func beginTransaction(
        entries: [TransactionEntry],
        changes: [VariableChange],
        storage: PreparedStorage
    ) throws -> URL {
        let transactionURL = storage.transactions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backupsURL = transactionURL.appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        var filenames: [String] = []
        for entry in entries {
            let source = variableURL(forNormalizedKey: entry.normalizedKey, storage: storage)
            let filename = source.lastPathComponent
            filenames.append(filename)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: backupsURL.appendingPathComponent(filename))
            }
        }
        let journal = TransactionJournal(
            variableFilenames: filenames,
            historyFilenames: changes.map { "\($0.id.uuidString).json" }
        )
        try encoder.encode(journal).write(
            to: transactionURL.appendingPathComponent("journal.json"),
            options: [.atomic]
        )
        return transactionURL
    }

    private func rollbackTransaction(at transactionURL: URL, storage: PreparedStorage) throws {
        let journalURL = transactionURL.appendingPathComponent("journal.json")
        guard fileManager.fileExists(atPath: journalURL.path) else {
            try? fileManager.removeItem(at: transactionURL)
            return
        }
        let journal = try decoder.decode(TransactionJournal.self, from: Data(contentsOf: journalURL))
        let backupsURL = transactionURL.appendingPathComponent("Backups", isDirectory: true)
        for filename in journal.variableFilenames {
            let target = storage.variables.appendingPathComponent(filename)
            let backup = backupsURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: backup.path) {
                try Data(contentsOf: backup).write(to: target, options: [.atomic])
            } else if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
        }
        for filename in journal.historyFilenames {
            let historyURL = storage.history.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: historyURL.path) {
                try? fileManager.removeItem(at: historyURL)
            }
        }
        try fileManager.removeItem(at: transactionURL)
    }

    private func recoverTransactions(storage: PreparedStorage) throws {
        let transactions = try fileManager.contentsOfDirectory(
            at: storage.transactions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for transaction in transactions {
            try rollbackTransaction(at: transaction, storage: storage)
        }
    }

    private func compareForSorting(_ lhs: VariableValue, _ rhs: VariableValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.integer(let left), .integer(let right)):
            left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case (.integer(let left), .number(let right)):
            Double(left) == right ? .orderedSame : (Double(left) < right ? .orderedAscending : .orderedDescending)
        case (.number(let left), .integer(let right)):
            left == Double(right) ? .orderedSame : (left < Double(right) ? .orderedAscending : .orderedDescending)
        case (.number(let left), .number(let right)):
            left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case (.date(let left), .date(let right)):
            left.compare(right)
        case (.boolean(let left), .boolean(let right)):
            left == right ? .orderedSame : (left ? .orderedDescending : .orderedAscending)
        default:
            lhs.jsonString.localizedStandardCompare(rhs.jsonString)
        }
    }

    private func pruneHistory(storage: PreparedStorage, maximum: Int = 500) throws {
        let files = try fileManager.contentsOfDirectory(
            at: storage.history,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard files.count > maximum else { return }
        let sorted = files.compactMap { url -> (url: URL, date: Date)? in
            guard let data = try? coordinatedReadData(
                at: url
            ),
            let change = try? decoder.decode(
                VariableChange.self,
                from: data
            ) else {
                return nil
            }
            return (url, change.timestamp)
        }.sorted {
            $0.date < $1.date
        }
        let expiredHistory = sorted.prefix(
            max(0, sorted.count - maximum)
        )

        guard !expiredHistory.isEmpty else {
            return
        }

        for item in expiredHistory {
            try coordinatedRemoveItem(at: item.url)
        }

        // Once old history is gone, file attachments that are no longer
        // reachable from current state or retained history can be reclaimed.
        _ = try removeOrphanedAttachments(
            storage: storage
        )
    }

    private func normalizedKey(_ key: String) throws -> String {
        let normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard !normalized.isEmpty else { throw BywayError.emptyKey }
        return normalized
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalizedFolderName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw BywayError.invalidValue("The folder name cannot be empty.")
        }
        return normalized
    }

    private func variableURL(forNormalizedKey key: String, storage: PreparedStorage) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return storage.variables.appendingPathComponent(filename).appendingPathExtension("json")
    }

    private func attachmentURL(for file: StoredFile, storage: PreparedStorage) -> URL {
        let ext = (file.filename as NSString).pathExtension
        let name = ext.isEmpty ? file.id.uuidString : "\(file.id.uuidString).\(ext)"
        return storage.attachments.appendingPathComponent(name)
    }

    private func folderURL(id: UUID, storage: PreparedStorage) -> URL {
        storage.folders.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func fileReferences(in value: VariableValue) -> [StoredFile] {
        switch value {
        case .file(let file): [file]
        case .array(let values): values.flatMap(fileReferences)
        case .dictionary(let values): values.values.flatMap(fileReferences)
        default: []
        }
    }

    private func fileReferenceIDs(in value: VariableValue?) -> Set<UUID> {
        guard let value else { return [] }
        return Set(fileReferences(in: value).map(\.id))
    }
}

struct VariableRepositorySnapshot: Sendable {
    var variables: [GlobalVariable]
    var folders: [VariableFolder]
    var changes: [VariableChange]
    var storageStatus: StorageStatus
    var quarantinedFileCount: Int
}


enum VariableConflictResolver {
    static func preferredIndex(
        in variables: [GlobalVariable]
    ) -> Int? {
        variables.indices.max { leftIndex, rightIndex in
            prefers(
                variables[rightIndex],
                over: variables[leftIndex]
            )
        }
    }

    static func preferred(
        from variables: [GlobalVariable]
    ) -> GlobalVariable? {
        guard let index = preferredIndex(in: variables) else {
            return nil
        }
        return variables[index]
    }

    private static func prefers(
        _ candidate: GlobalVariable,
        over current: GlobalVariable
    ) -> Bool {
        if candidate.revision != current.revision {
            return candidate.revision > current.revision
        }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        return candidate.id.uuidString > current.id.uuidString
    }
}
