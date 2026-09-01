import CryptoKit
import Foundation

actor VariableRepository {
    static let shared = VariableRepository()

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

    func list(
        matching query: String = "",
        includeExpired: Bool = false,
        tag: String? = nil
    ) throws -> [GlobalVariable] {
        let storage = try prepareStorage()
        let urls = try fileManager.contentsOfDirectory(
            at: storage.variables,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(GlobalVariable.self, from: data)
            }
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

        let variable = try decoder.decode(GlobalVariable.self, from: Data(contentsOf: url))
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
        return try fileManager.contentsOfDirectory(
            at: storage.folders,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? decoder.decode(VariableFolder.self, from: Data(contentsOf: $0)) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
            try fileManager.removeItem(at: url)
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
        let previousData = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
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
        } catch {
            if let previousData {
                try? previousData.write(to: url, options: [.atomic])
            } else {
                try? fileManager.removeItem(at: url)
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
        let oldURL = variableURL(forNormalizedKey: oldNormalized, storage: storage)
        let newURL = variableURL(forNormalizedKey: newNormalized, storage: storage)

        if oldNormalized != newNormalized, fileManager.fileExists(atPath: newURL.path) {
            throw BywayError.duplicateKey(newKey)
        }

        let previous = variable
        variable.key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        variable.updatedAt = .now
        variable.revision += 1
        try write(variable, to: newURL)
        if oldURL != newURL, fileManager.fileExists(atPath: oldURL.path) {
            try fileManager.removeItem(at: oldURL)
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
        return variable
    }

    func delete(key: String) throws {
        let variable = try variable(forKey: key, includeExpired: true)
        let storage = try prepareStorage()
        let url = variableURL(forNormalizedKey: try normalizedKey(key), storage: storage)
        let originalData = try Data(contentsOf: url)
        try fileManager.removeItem(at: url)
        do {
            try recordChange(VariableChange(
                variableID: variable.id,
                key: variable.key,
                operation: .delete,
                previous: variable,
                current: nil
            ), storage: storage)
        } catch {
            try? originalData.write(to: url, options: [.atomic])
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
                    existing = try decoder.decode(GlobalVariable.self, from: Data(contentsOf: url))
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
                    try fileManager.removeItem(at: url)
                }
            }
            for change in changes {
                let url = storage.history.appendingPathComponent("\(change.id.uuidString).json")
                try encoder.encode(change).write(to: url, options: [.atomic])
            }
            try pruneHistory(storage: storage)
            try fileManager.removeItem(at: transactionURL)
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
        let storage = try prepareStorage()
        let file = StoredFile(filename: filename, contentType: contentType, byteCount: data.count)
        let url = attachmentURL(for: file, storage: storage)
        try data.write(to: url, options: [.atomic])
        return file
    }

    func fileData(for file: StoredFile) throws -> Data {
        let storage = try prepareStorage()
        let url = attachmentURL(for: file, storage: storage)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BywayError.missingFile(file.filename)
        }
        return try Data(contentsOf: url)
    }

    func history(limit: Int = 200) throws -> [VariableChange] {
        let storage = try prepareStorage()
        let urls = try fileManager.contentsOfDirectory(
            at: storage.history,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(VariableChange.self, from: Data(contentsOf: $0)) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(0, limit))
            .map { $0 }
    }

    @discardableResult
    func restore(changeID: UUID) throws -> GlobalVariable {
        let storage = try prepareStorage()
        let changeURL = storage.history.appendingPathComponent("\(changeID.uuidString).json")
        let change = try decoder.decode(VariableChange.self, from: Data(contentsOf: changeURL))
        guard var snapshot = change.previous ?? change.current else {
            throw BywayError.invalidValue("This history item has no restorable snapshot.")
        }
        snapshot.updatedAt = .now
        snapshot.revision += 1
        let url = variableURL(forNormalizedKey: try normalizedKey(snapshot.key), storage: storage)
        let existing = try? decoder.decode(GlobalVariable.self, from: Data(contentsOf: url))
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

    @discardableResult
    func importArchive(data: Data, strategy: ImportStrategy) throws -> Int {
        let archive = try decoder.decode(BywayArchive.self, from: data)
        guard archive.version <= BywayArchive.currentVersion else {
            throw BywayError.invalidValue("This archive was created by a newer version of byway.")
        }

        let storage = try prepareStorage()
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

        let existingVariables = try list(includeExpired: true)
        let existingKeys = Set(try existingVariables.map { try normalizedKey($0.key) })
        var mutations: [VariableMutation] = strategy == .replaceAll
            ? existingVariables.map { .delete(key: $0.key) }
            : []
        var variablesToImport: [GlobalVariable] = []
        for variable in archive.variables {
            let normalized = try normalizedKey(variable.key)
            if strategy == .keepExisting && existingKeys.contains(normalized) { continue }
            variablesToImport.append(variable)
            mutations.append(.replace(variable))
        }

        let attachmentBackup = fileManager.temporaryDirectory
            .appendingPathComponent("byway-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: attachmentBackup, withIntermediateDirectories: true)
        var writtenAttachments: [(target: URL, backup: URL?)] = []
        do {
            for variable in variablesToImport {
                for file in fileReferences(in: variable.value) {
                    guard let attachment = archive.attachments[file.id.uuidString] else { continue }
                    let target = attachmentURL(for: file, storage: storage)
                    var backup: URL?
                    if fileManager.fileExists(atPath: target.path) {
                        let backupURL = attachmentBackup.appendingPathComponent(target.lastPathComponent)
                        try fileManager.copyItem(at: target, to: backupURL)
                        backup = backupURL
                    }
                    try attachment.write(to: target, options: [.atomic])
                    writtenAttachments.append((target, backup))
                }
            }
            _ = try applyTransaction(mutations)
            for folder in archive.folders {
                try write(folder, storage: storage)
            }
            if strategy == .replaceAll {
                let retainedIDs = Set(archive.folders.map(\.id))
                for folder in try listFolders() where !retainedIDs.contains(folder.id) {
                    let url = folderURL(id: folder.id, storage: storage)
                    try? fileManager.removeItem(at: url)
                }
            }
            try fileManager.removeItem(at: attachmentBackup)
        } catch {
            for item in writtenAttachments.reversed() {
                if let backup = item.backup {
                    try? Data(contentsOf: backup).write(to: item.target, options: [.atomic])
                } else {
                    try? fileManager.removeItem(at: item.target)
                }
            }
            try? fileManager.removeItem(at: attachmentBackup)
            throw error
        }
        return variablesToImport.count
    }

    private struct PreparedStorage {
        var status: StorageStatus
        var variables: URL
        var attachments: URL
        var folders: URL
        var history: URL
        var transactions: URL
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
        for directory in [variables, attachments, folders, history, transactions] {
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
            transactions: transactions
        )
        try recoverTransactions(storage: storage)
        return storage
    }

    private func migrateLocalData(to destination: URL) throws {
        let local = try BywayStorage.localRoot()
        guard local != destination, fileManager.fileExists(atPath: local.path) else { return }
        for directoryName in ["Variables", "Attachments", "Folders", "History"] {
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

    private func write(_ variable: GlobalVariable, to url: URL) throws {
        try encoder.encode(variable).write(to: url, options: [.atomic])
    }

    private func write(_ folder: VariableFolder, storage: PreparedStorage) throws {
        try encoder.encode(folder).write(to: folderURL(id: folder.id, storage: storage), options: [.atomic])
    }

    private func recordChange(_ change: VariableChange, storage: PreparedStorage) throws {
        let url = storage.history.appendingPathComponent("\(change.id.uuidString).json")
        try encoder.encode(change).write(to: url, options: [.atomic])
        try pruneHistory(storage: storage)
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
            guard let data = try? Data(contentsOf: url),
                  let change = try? decoder.decode(VariableChange.self, from: data) else {
                return nil
            }
            return (url, change.timestamp)
        }.sorted {
            $0.date < $1.date
        }
        for item in sorted.prefix(max(0, sorted.count - maximum)) {
            try? fileManager.removeItem(at: item.url)
        }
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
}
