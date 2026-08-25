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
        let existing: GlobalVariable? = try? decoder.decode(
            GlobalVariable.self,
            from: Data(contentsOf: url)
        )

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
        try recordChange(
            VariableChange(
                variableID: variable.id,
                key: variable.key,
                operation: existing == nil ? .create : .update,
                previous: existing,
                current: variable
            ),
            storage: storage
        )
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
        try fileManager.removeItem(at: url)
        try recordChange(
            VariableChange(
                variableID: variable.id,
                key: variable.key,
                operation: .delete,
                previous: variable,
                current: nil
            ),
            storage: storage
        )
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
        let result: Double
        switch variable.value {
        case .integer(let value): result = Double(value) + amount
        case .number(let value): result = value + amount
        default:
            throw BywayError.typeMismatch(expected: .number, actual: variable.value.kind)
        }

        if case .integer = variable.value,
           floor(result) == result,
           result >= Double(Int64.min),
           result <= Double(Int64.max) {
            try set(key: variable.key, value: .integer(Int64(result)), expiresAt: variable.expiresAt)
        } else {
            try set(key: variable.key, value: .number(result), expiresAt: variable.expiresAt)
        }
        return result
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
    func setDictionaryEntry(key: String, field: String, value: VariableValue) throws -> [String: VariableValue] {
        let variable = try variable(forKey: key)
        guard case .dictionary(var dictionary) = variable.value else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: variable.value.kind)
        }
        let trimmedField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedField.isEmpty else {
            throw BywayError.invalidValue("The dictionary field cannot be empty.")
        }
        dictionary[trimmedField] = value
        try set(key: variable.key, value: .dictionary(dictionary), expiresAt: variable.expiresAt)
        return dictionary
    }

    @discardableResult
    func removeDictionaryEntry(key: String, field: String) throws -> [String: VariableValue] {
        let variable = try variable(forKey: key)
        guard case .dictionary(var dictionary) = variable.value else {
            throw BywayError.typeMismatch(expected: .dictionary, actual: variable.value.kind)
        }
        dictionary.removeValue(forKey: field)
        try set(key: variable.key, value: .dictionary(dictionary), expiresAt: variable.expiresAt)
        return dictionary
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

    func exportArchive(variableIDs: Set<UUID>? = nil) throws -> Data {
        let variables = try list(includeExpired: true).filter { variable in
            variableIDs.map { $0.contains(variable.id) } ?? true
        }
        var attachments: [String: Data] = [:]
        for file in variables.flatMap({ fileReferences(in: $0.value) }) {
            attachments[file.id.uuidString] = try? fileData(for: file)
        }
        let archive = BywayArchive(variables: variables, attachments: attachments)
        return try encoder.encode(archive)
    }

    @discardableResult
    func importArchive(data: Data, strategy: ImportStrategy) throws -> Int {
        let archive = try decoder.decode(BywayArchive.self, from: data)
        guard archive.version <= BywayArchive.currentVersion else {
            throw BywayError.invalidValue("This archive was created by a newer version of byway.")
        }

        let storage = try prepareStorage()
        if strategy == .replaceAll {
            for variable in try list(includeExpired: true) {
                let url = variableURL(forNormalizedKey: try normalizedKey(variable.key), storage: storage)
                try? fileManager.removeItem(at: url)
            }
        }

        var count = 0
        for variable in archive.variables {
            let normalized = try normalizedKey(variable.key)
            let url = variableURL(forNormalizedKey: normalized, storage: storage)
            let exists = fileManager.fileExists(atPath: url.path)
            if exists && strategy == .keepExisting { continue }

            for file in fileReferences(in: variable.value) {
                if let data = archive.attachments[file.id.uuidString] {
                    try data.write(to: attachmentURL(for: file, storage: storage), options: [.atomic])
                }
            }
            let previous = exists
                ? try? decoder.decode(GlobalVariable.self, from: Data(contentsOf: url))
                : nil
            try write(variable, to: url)
            try recordChange(
                VariableChange(
                    variableID: variable.id,
                    key: variable.key,
                    operation: .importVariables,
                    previous: previous,
                    current: variable
                ),
                storage: storage
            )
            count += 1
        }
        return count
    }

    private struct PreparedStorage {
        var status: StorageStatus
        var variables: URL
        var attachments: URL
        var history: URL
    }

    private func prepareStorage() throws -> PreparedStorage {
        let status = try BywayStorage.preferredRoot()
        try fileManager.createDirectory(at: status.rootURL, withIntermediateDirectories: true)

        let variables = status.rootURL.appendingPathComponent("Variables", isDirectory: true)
        let attachments = status.rootURL.appendingPathComponent("Attachments", isDirectory: true)
        let history = status.rootURL.appendingPathComponent("History", isDirectory: true)
        for directory in [variables, attachments, history] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if status.location == .iCloud, lastStatus?.location != .iCloud {
            try migrateLocalData(to: status.rootURL)
        }
        lastStatus = status
        return PreparedStorage(status: status, variables: variables, attachments: attachments, history: history)
    }

    private func migrateLocalData(to destination: URL) throws {
        let local = try BywayStorage.localRoot()
        guard local != destination, fileManager.fileExists(atPath: local.path) else { return }
        for directoryName in ["Variables", "Attachments", "History"] {
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

    private func recordChange(_ change: VariableChange, storage: PreparedStorage) throws {
        let url = storage.history.appendingPathComponent("\(change.id.uuidString).json")
        try encoder.encode(change).write(to: url, options: [.atomic])
        try pruneHistory(storage: storage)
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

    private func fileReferences(in value: VariableValue) -> [StoredFile] {
        switch value {
        case .file(let file): [file]
        case .array(let values): values.flatMap(fileReferences)
        case .dictionary(let values): values.values.flatMap(fileReferences)
        default: []
        }
    }
}
