import SwiftUI
import SwiftData

/// Price fields shared by the tariff form and the first price of a new contract.
struct PriceFields: View {
    let meter: Meter
    @Binding var priceText: String
    @Binding var baseFeeText: String
    @Binding var feedInText: String

    var body: some View {
        HStack {
            TextField("Preis pro \(meter.unitLabel)", text: $priceText)
                .keyboardType(.decimalPad)
            Text("€").foregroundStyle(.secondary)
        }
        HStack {
            TextField("Grundgebühr pro Monat", text: $baseFeeText)
                .keyboardType(.decimalPad)
            Text("€").foregroundStyle(.secondary)
        }
        if meter.type == .electricityFeedIn {
            HStack {
                TextField("Einspeisevergütung pro \(meter.unitLabel)", text: $feedInText)
                    .keyboardType(.decimalPad)
                Text("€").foregroundStyle(.secondary)
            }
        }
    }
}

/// Adds or edits one price (tariff), optionally inside a contract.
struct TariffFormSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meter: Meter
    var contract: Contract?
    /// The price to edit; `nil` adds a new one.
    var tariff: Tariff?

    @State private var priceText = ""
    @State private var baseFeeText = ""
    @State private var feedInText = ""
    @State private var validFrom: Date = .now
    @State private var didLoad = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preise") {
                    PriceFields(meter: meter, priceText: $priceText, baseFeeText: $baseFeeText, feedInText: $feedInText)
                }
                Section {
                    DatePicker("Gültig ab", selection: $validFrom, displayedComponents: .date)
                } header: {
                    Text("Gültigkeit")
                } footer: {
                    Text("Der vorherige Preis endet automatisch an diesem Tag. Ein Datum in der Zukunft legt den Preis als geplant an.")
                }
                if tariff != nil {
                    Section {
                        Button("Preis löschen", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(tariff == nil ? (contract == nil ? "Neuer Preis" : "Preisanpassung") : "Preis bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(Formatting.parseDecimal(priceText) == nil)
                }
            }
            .confirmationDialog("Preis löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let tariff else { return }
        priceText = Formatting.inputString(tariff.pricePerUnit)
        baseFeeText = tariff.baseFeePerMonth == 0 ? "" : Formatting.inputString(tariff.baseFeePerMonth)
        feedInText = tariff.feedInPricePerUnit.map(Formatting.inputString) ?? ""
        validFrom = tariff.validFrom
    }

    private func save() {
        guard let price = Formatting.parseDecimal(priceText) else { return }
        let base = Formatting.parseDecimal(baseFeeText) ?? 0
        let feed = Formatting.parseDecimal(feedInText)
        let entry: Tariff
        if let tariff {
            tariff.pricePerUnit = price
            tariff.baseFeePerMonth = base
            tariff.feedInPricePerUnit = feed
            tariff.validFrom = validFrom
            entry = tariff
        } else {
            entry = Tariff(meter: meter, pricePerUnit: price, baseFeePerMonth: base, feedInPricePerUnit: feed, validFrom: validFrom)
            entry.contract = contract
            context.insert(entry)
        }
        ValidityChain.relink(meter.tariffs.filter { $0.id != entry.id } + [entry])
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let tariff else { return }
        let id = tariff.id
        context.delete(tariff)
        ValidityChain.relink(meter.tariffs.filter { $0.id != id })
        try? context.save()
        dismiss()
    }
}
