import Foundation

@main
struct AdvancedCoreIntegration {
    static func main() async throws {
        let repository = VariableRepository()

        let maximum = try VariableValue.fromJSON("9223372036854775807")
        guard maximum == .integer(Int64.max) else { throw TestFailure("Int64.max was not preserved") }
        let overflow = try VariableValue.fromJSON("9223372036854775808")
        guard case .number = overflow else { throw TestFailure("Out-of-range integer was not converted safely") }
        guard try VariableValue.fromJSON("null") == .null else { throw TestFailure("Null was not preserved") }

        let batch = try await repository.applyTransaction([
            .set(key: "TEST.Mode", value: .text("Auto"), expiresAt: nil),
            .set(key: "TEST.Active", value: .boolean(true), expiresAt: nil),
            .set(key: "TEST.Dictionary", value: .dictionary([:]), expiresAt: nil),
            .ensure(key: "TEST.List", value: .array([]), expiresAt: nil)
        ])
        guard batch.createdCount == 4 else { throw TestFailure("Batch did not create four variables") }

        let failedTransaction: Bool
        do {
            _ = try await repository.applyTransaction([
                .set(key: "TEST.Mode", value: .text("Should Roll Back"), expiresAt: nil),
                .setDictionaryEntry(key: "TEST.Active", path: "nested.value", value: .integer(1))
            ])
            failedTransaction = false
        } catch {
            failedTransaction = true
        }
        guard failedTransaction else { throw TestFailure("Invalid transaction unexpectedly succeeded") }
        guard try await repository.variable(forKey: "TEST.Mode").value == .text("Auto") else {
            throw TestFailure("A failed transaction did not roll back")
        }

        _ = try await repository.setDictionaryEntry(
            key: "TEST.Dictionary",
            field: "Auto.Portrait.Selection",
            value: .null
        )
        let nested = try await repository.dictionaryEntry(key: "TEST.Dictionary", path: "Auto.Portrait.Selection")
        guard nested == .null else { throw TestFailure("Nested null dictionary entry was not preserved") }
        guard try await repository.dictionaryEntry(key: "TEST.Dictionary", path: "Auto.Portrait.Missing") == nil else {
            throw TestFailure("Missing dictionary entry was not distinguishable")
        }

        _ = try await repository.append(key: "TEST.List", values: [
            .dictionary(["score": .integer(3), "name": .text("C")]),
            .dictionary(["score": .integer(1), "name": .text("A")]),
            .dictionary(["score": .integer(1), "name": .text("A")])
        ])
        guard try await repository.listCount(key: "TEST.List") == 3 else { throw TestFailure("List count failed") }
        let matches = try await repository.findListItems(key: "TEST.List", path: "score", equalTo: .integer(1))
        guard matches.count == 2 else { throw TestFailure("List find failed") }
        let unique = try await repository.removeDuplicateListItems(key: "TEST.List")
        guard unique.count == 2 else { throw TestFailure("Remove duplicates failed") }
        let sorted = try await repository.sortList(key: "TEST.List", path: "score")
        guard try sorted.first?.value(atPath: "score") == .integer(1) else { throw TestFailure("List sort failed") }
        _ = try await repository.updateListItem(key: "TEST.List", index: 0, value: .text("Updated"))
        _ = try await repository.deleteListItem(key: "TEST.List", index: 1)
        guard try await repository.listCount(key: "TEST.List") == 1 else { throw TestFailure("List update/delete failed") }

        let eventOne = BywayEvent(
            category: "Music",
            action: "Shazam",
            timestamp: Date(timeIntervalSince1970: 100),
            details: ["title": .text("One")]
        )
        let eventTwo = BywayEvent(
            category: "Navigation",
            action: "Start",
            timestamp: Date(timeIntervalSince1970: 200),
            details: ["destination": .text("Home")]
        )
        _ = try await repository.appendEvent(event: eventOne)
        _ = try await repository.appendEvent(event: eventTwo)
        let music = try await repository.queryEvents(category: "music")
        guard music.map(\.id) == [eventOne.id] else { throw TestFailure("Event category query failed") }
        guard try await repository.lastEvent().id == eventTwo.id else { throw TestFailure("Get last event failed") }

        _ = try await repository.set(key: "TEST.Null", value: .null)
        guard try await repository.exists(key: "TEST.Null") else { throw TestFailure("Null variable did not count as existing") }
        let missingExists = try await repository.exists(key: "TEST.Missing")
        guard !missingExists else { throw TestFailure("Missing variable counted as existing") }

        let folder = try await repository.createFolder(name: "Shared Tests")
        guard try await repository.listFolders().contains(where: { $0.id == folder.id }) else {
            throw TestFailure("An empty folder was not persisted")
        }
        let variablesToMove = try await [
            repository.variable(forKey: "TEST.Mode"),
            repository.variable(forKey: "TEST.Null")
        ]
        let moved = try await repository.moveVariables(ids: Set(variablesToMove.map(\.id)), to: folder.id)
        guard moved == 2,
              try await repository.variable(forKey: "TEST.Mode").folderID == folder.id,
              try await repository.variable(forKey: "TEST.Null").folderID == folder.id else {
            throw TestFailure("Batch folder move failed")
        }

        let archive = try await repository.exportArchive(variableKeys: ["TEST.Mode", "TEST.Null"])
        let deleted = try await repository.deleteVariables(ids: Set(variablesToMove.map(\.id)))
        guard deleted == 2 else { throw TestFailure("Batch variable deletion failed") }
        try await repository.deleteFolder(id: folder.id)
        let imported = try await repository.importArchive(data: archive, strategy: .overwrite)
        guard imported == 2,
              try await repository.variable(forKey: "TEST.Mode").value == .text("Auto"),
              try await repository.variable(forKey: "TEST.Null").value == .null,
              try await repository.variable(forKey: "TEST.Mode").folderID == folder.id,
              try await repository.listFolders().contains(where: { $0.id == folder.id }) else {
            throw TestFailure("Selective export/import did not preserve folders")
        }

        try await repository.deleteFolder(id: folder.id)
        guard try await repository.variable(forKey: "TEST.Mode").folderID == nil,
              try await repository.variable(forKey: "TEST.Null").folderID == nil else {
            throw TestFailure("Deleting a folder did not retain its variables outside a folder")
        }

        print("PASS: transactions, rollback, nested dictionaries, null, lists, events, folders, batch operations, and archives")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
