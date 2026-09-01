import AppIntents
import Foundation

@main
struct AdvancedIntentIntegration {
    static func main() async throws {
        let repository = VariableRepository.shared

        let batch = BatchSetVariablesIntent()
        batch.json = """
        {
          "INTENT.Dictionary": {"$type":"dictionary","value":{"Auto":{"Portrait":null}}},
          "INTENT.Location": {"$type":"location","latitude":25.6866,"longitude":-100.3161,"name":"Monterrey"},
          "INTENT.Measurement": {"$type":"measurement","value":24.6,"unit":"°C"}
        }
        """
        batch.expiresAt = nil
        _ = try await batch.perform()

        let dictionary = GetDictionaryEntryIntent()
        dictionary.key = "INTENT.Dictionary"
        dictionary.path = "Auto.Portrait"
        _ = try await dictionary.perform()

        let location = GetLocationDetailsIntent()
        location.key = "INTENT.Location"
        _ = try await location.perform()

        let measurement = GetMeasurementDetailsIntent()
        measurement.key = "INTENT.Measurement"
        _ = try await measurement.perform()

        let appendEvent = AppendEventIntent()
        appendEvent.key = "HISTORY.Events"
        appendEvent.category = "Test"
        appendEvent.action = "Intent"
        appendEvent.detailsJSON = "{\"passed\":true}"
        appendEvent.date = Date(timeIntervalSince1970: 123)
        appendEvent.uuid = nil
        _ = try await appendEvent.perform()

        let modeChange = SetSystemModeIntent()
        modeChange.mode = "Auto"
        modeChange.source = "SIRI"
        _ = try await modeChange.perform()
        let storedMode = try await VariableRepository.shared.variable(forKey: "SYS.Mode")
        guard storedMode.value == .text("Auto") else { throw IntentTestFailure() }
        let storedAction = try await VariableRepository.shared.variable(forKey: "SYS.LastAction")
        guard storedAction.value == .text("MODE_CHANGE") else { throw IntentTestFailure() }

        let query = QueryEventsIntent()
        query.key = "HISTORY.Events"
        query.category = "Test"
        query.action = nil
        query.startDate = nil
        query.endDate = nil
        query.limit = 10
        query.order = .newestFirst
        _ = try await query.perform()

        let ensure = EnsureVariableIntent()
        ensure.key = "INTENT.Null"
        ensure.json = "null"
        ensure.expiresAt = nil
        _ = try await ensure.perform()
        ensure.json = "\"must not replace null\""
        _ = try await ensure.perform()

        let transaction = RunVariableTransactionIntent()
        transaction.json = """
        [
          {"operation":"set","key":"INTENT.Mode","value":"Auto"},
          {"operation":"append","key":"HISTORY.Events","value":{"id":"00000000-0000-0000-0000-000000000001","category":"Test","action":"Transaction","timestamp":"1970-01-01T00:02:04Z","details":{}}}
        ]
        """
        _ = try await transaction.perform()

        let metadata = GetVariableMetadataIntent()
        metadata.key = "INTENT.Null"
        _ = try await metadata.perform()

        guard try await repository.variable(forKey: "INTENT.Null").value == .null,
              try await repository.variable(forKey: "INTENT.Mode").value == .text("Auto"),
              try await repository.queryEvents(category: "Test").count == 2 else {
            throw IntentTestFailure()
        }

        _ = try await GenerateUUIDIntent().perform()
        print("PASS: advanced App Intents execute against shared repository")
    }
}

struct IntentTestFailure: Error {}
