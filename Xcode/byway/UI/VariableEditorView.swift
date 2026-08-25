import SwiftUI
import UniformTypeIdentifiers

private struct PendingFile {
    var data: Data
    var filename: String
    var contentType: String
}

struct VariableEditorView: View {
    @Environment(VariableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let variable: GlobalVariable?

    @State private var key: String
    @State private var kind: VariableKind
    @State private var textValue: String
    @State private var booleanValue: Bool
    @State private var integerValue: String
    @State private var numberValue: String
    @State private var measurementUnit: String
    @State private var jsonValue: String
    @State private var dateValue: Date
    @State private var latitude: String
    @State private var longitude: String
    @State private var locationName: String
    @State private var urlValue: String
    @State private var base64Value: String
    @State private var tags: String
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var pendingFile: PendingFile?
    @State private var isImportingFile = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(variable: GlobalVariable?) {
        self.variable = variable
        let value = variable?.value ?? .text("")
        _key = State(initialValue: variable?.key ?? "")
        _kind = State(initialValue: value.kind)
        _textValue = State(initialValue: value.textValue ?? "")
        _booleanValue = State(initialValue: value.booleanValue ?? false)
        _integerValue = State(initialValue: value.integerValue.map { String($0) } ?? "0")
        _numberValue = State(initialValue: value.numberValue.map { String($0) } ?? "0")
        _measurementUnit = State(initialValue: value.measurementValue?.unitSymbol ?? "")
        _jsonValue = State(initialValue: value.collectionJSON ?? "[]")
        _dateValue = State(initialValue: value.dateValue ?? .now)
        _latitude = State(initialValue: value.locationValue.map { String($0.latitude) } ?? "")
        _longitude = State(initialValue: value.locationValue.map { String($0.longitude) } ?? "")
        _locationName = State(initialValue: value.locationValue?.name ?? "")
        _urlValue = State(initialValue: value.urlValue?.absoluteString ?? "https://")
        _base64Value = State(initialValue: value.dataValue?.base64EncodedString() ?? "")
        _tags = State(initialValue: variable?.tags.joined(separator: ", ") ?? "")
        _notes = State(initialValue: variable?.notes ?? "")
        _isFavorite = State(initialValue: variable?.isFavorite ?? false)
        _hasExpiration = State(initialValue: variable?.expiresAt != nil)
        _expirationDate = State(initialValue: variable?.expiresAt ?? Date.now.addingTimeInterval(86_400))
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Key", text: $key, prompt: Text("example.last-route"))
                Picker("Type", selection: $kind) {
                    ForEach(VariableKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
            }

            Section("Value") {
                valueEditor
            }

            Section("Organization") {
                TextField("Tags separated by commas", text: $tags)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                Toggle("Favorite", isOn: $isFavorite)
            }

            Section("Expiration") {
                Toggle("Expire automatically", isOn: $hasExpiration)
                if hasExpiration {
                    DatePicker("Expiration date", selection: $expirationDate)
                }
            }
        }
        .navigationTitle(variable == nil ? "New variable" : "Edit variable")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
                pendingFile = PendingFile(
                    data: try Data(contentsOf: url),
                    filename: url.lastPathComponent,
                    contentType: values.contentType?.identifier ?? UTType.data.identifier
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Could not save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch kind {
        case .text:
            TextField("Text", text: $textValue, axis: .vertical)
                .lineLimit(3...12)
        case .boolean:
            Toggle("Value", isOn: $booleanValue)
        case .integer:
            TextField("Integer", text: $integerValue)
#if os(iOS)
                .keyboardType(.numbersAndPunctuation)
#endif
        case .number:
            TextField("Number", text: $numberValue)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
        case .duration:
            TextField("Seconds", text: $numberValue)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
        case .measurement:
            TextField("Value", text: $numberValue)
            TextField("Unit symbol", text: $measurementUnit, prompt: Text("km, kg, °C…"))
        case .array, .dictionary:
            TextEditor(text: $jsonValue)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
            Text(kind == .array ? "Enter a JSON array." : "Enter a JSON object.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .date:
            DatePicker("Date", selection: $dateValue)
        case .location:
            TextField("Name (optional)", text: $locationName)
            TextField("Latitude", text: $latitude)
            TextField("Longitude", text: $longitude)
        case .url:
            TextField("URL", text: $urlValue)
        case .data:
            TextEditor(text: $base64Value)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
            Text("Base64-encoded data")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .file:
            Button {
                isImportingFile = true
            } label: {
                Label(pendingFile?.filename ?? variable?.value.fileValue?.filename ?? "Choose file", systemImage: "doc.badge.plus")
            }
        case .null:
            Label("Null has no value", systemImage: "nosign")
                .foregroundStyle(.secondary)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let value = try await makeValue()
            try await store.save(
                existingID: variable?.id,
                key: key,
                value: value,
                tags: tags.split(separator: ",").map(String.init),
                notes: notes,
                isFavorite: isFavorite,
                expiresAt: hasExpiration ? expirationDate : nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeValue() async throws -> VariableValue {
        switch kind {
        case .text:
            return .text(textValue)
        case .boolean:
            return .boolean(booleanValue)
        case .integer:
            guard let value = Int64(integerValue) else {
                throw BywayError.invalidValue("Enter a valid 64-bit integer.")
            }
            return .integer(value)
        case .number:
            guard let value = Double(numberValue) else {
                throw BywayError.invalidValue("Enter a valid number.")
            }
            return .number(value)
        case .duration:
            guard let value = Double(numberValue), value >= 0 else {
                throw BywayError.invalidValue("Enter a valid duration in seconds.")
            }
            return .duration(value)
        case .measurement:
            guard let value = Double(numberValue), !measurementUnit.isEmpty else {
                throw BywayError.invalidValue("Enter a measurement value and unit symbol.")
            }
            return .measurement(BywayMeasurement(value: value, unitSymbol: measurementUnit))
        case .array:
            let value = try VariableValue.fromJSON(jsonValue)
            guard case .array = value else {
                throw BywayError.invalidValue("The value must be a JSON array.")
            }
            return value
        case .dictionary:
            let value = try VariableValue.fromJSON(jsonValue)
            guard case .dictionary = value else {
                throw BywayError.invalidValue("The value must be a JSON object.")
            }
            return value
        case .date:
            return .date(dateValue)
        case .location:
            guard let latitude = Double(latitude), let longitude = Double(longitude),
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                throw BywayError.invalidValue("Enter valid latitude and longitude coordinates.")
            }
            return .location(BywayLocation(
                latitude: latitude,
                longitude: longitude,
                name: locationName.isEmpty ? nil : locationName
            ))
        case .url:
            guard let value = URL(string: urlValue), value.scheme != nil else {
                throw BywayError.invalidValue("Enter a valid absolute URL.")
            }
            return .url(value)
        case .data:
            guard let data = Data(base64Encoded: base64Value, options: [.ignoreUnknownCharacters]) else {
                throw BywayError.invalidValue("Enter valid Base64 data.")
            }
            return .data(data)
        case .file:
            if let pendingFile {
                let file = try await store.repository.saveFile(
                    data: pendingFile.data,
                    filename: pendingFile.filename,
                    contentType: pendingFile.contentType
                )
                return .file(file)
            }
            if let file = variable?.value.fileValue { return .file(file) }
            throw BywayError.invalidValue("Choose a file to store.")
        case .null:
            return .null
        }
    }
}

private extension VariableValue {
    var textValue: String? { if case .text(let value) = self { value } else { nil } }
    var booleanValue: Bool? { if case .boolean(let value) = self { value } else { nil } }
    var integerValue: Int64? { if case .integer(let value) = self { value } else { nil } }
    var numberValue: Double? {
        switch self {
        case .number(let value), .duration(let value): value
        case .measurement(let value): value.value
        default: nil
        }
    }
    var measurementValue: BywayMeasurement? { if case .measurement(let value) = self { value } else { nil } }
    var collectionJSON: String? {
        switch self {
        case .array, .dictionary: jsonString
        default: nil
        }
    }
    var dateValue: Date? { if case .date(let value) = self { value } else { nil } }
    var locationValue: BywayLocation? { if case .location(let value) = self { value } else { nil } }
    var urlValue: URL? { if case .url(let value) = self { value } else { nil } }
    var dataValue: Data? { if case .data(let value) = self { value } else { nil } }
    var fileValue: StoredFile? { if case .file(let value) = self { value } else { nil } }
}
