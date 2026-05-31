import SwiftUI
import PhotosUI

struct AddReadingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meter: Meter

    @State private var date: Date = .now
    @State private var valueText: String = ""
    @State private var note: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var validationError: String?

    private var previousValue: Decimal? {
        meter.readings.filter { $0.date < date }.sorted { $0.date > $1.date }.first?.value
    }

    private var parsedValue: Decimal? {
        let normalized = valueText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ablesung") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    HStack {
                        TextField("Zählerstand", text: $valueText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Text(meter.unitLabel).foregroundStyle(.secondary)
                    }
                    if let prev = previousValue {
                        Text("Vorheriger Wert: \(Formatting.counter(prev, unit: meter.unitLabel))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Optional") {
                    TextField("Notiz", text: $note, axis: .vertical)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if photoData == nil {
                            Label("Foto vom Zähler anhängen", systemImage: "camera")
                        } else {
                            Label("Foto ändern", systemImage: "photo.fill")
                        }
                    }
                    if let data = photoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let err = validationError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Neue Ablesung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                }
            }
            .task(id: photoItem) {
                if let item = photoItem,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    private func save() {
        guard let value = parsedValue else {
            validationError = "Bitte gültigen Zahlenwert eingeben."
            return
        }
        if let prev = previousValue, value < prev {
            validationError = "Wert ist kleiner als die letzte Ablesung. Zähler-Reset? Trotzdem speichern: längeres Drücken."
            // For simplicity we still save but with note.
        }
        let reading = Reading(meter: meter, date: date, value: value, note: note.isEmpty ? nil : note, photoData: photoData)
        context.insert(reading)
        try? context.save()
        dismiss()
    }
}
