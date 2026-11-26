import SwiftUI
import SwiftData

struct TariffOverviewView: View {
    @Query(sort: \Meter.createdAt) private var meters: [Meter]

    var body: some View {
        List {
            ForEach(meters) { meter in
                NavigationLink {
                    TariffListView(meter: meter)
                } label: {
                    HStack {
                        Image(systemName: meter.iconName)
                            .foregroundStyle(Color(hex: meter.colorHex) ?? .accentColor)
                        VStack(alignment: .leading) {
                            Text(meter.displayName)
                            if let bldg = meter.building {
                                Text(bldg.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(meter.tariffs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Tarife")
    }
}

struct TariffListView: View {
    @Environment(\.modelContext) private var context
    @Bindable var meter: Meter

    @State private var showAdd = false

    var sortedTariffs: [Tariff] { meter.tariffs.sorted { $0.validFrom > $1.validFrom } }

    var body: some View {
        List {
            ForEach(sortedTariffs) { t in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Formatting.currency(t.pricePerUnit) + "/\(meter.unitLabel)")
                            .font(.headline)
                        Spacer()
                        switch t.status(on: .now) {
                        case .planned:
                            Text("geplant").font(.caption).foregroundStyle(.orange)
                        case .current:
                            Text("aktuell").font(.caption).foregroundStyle(.green)
                        case .ended:
                            EmptyView()
                        }
                    }
                    if t.baseFeePerMonth != 0 {
                        Text("Grundgebühr: \(Formatting.currency(t.baseFeePerMonth))/Monat").font(.caption).foregroundStyle(.secondary)
                    }
                    if let feed = t.feedInPricePerUnit {
                        Text("Einspeisung: \(Formatting.currency(feed))/\(meter.unitLabel)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Gültig ab: \(Formatting.date.string(from: t.validFrom))" + (t.validTo.map { " bis \(Formatting.date.string(from: $0))" } ?? ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                let removed = offsets.map { sortedTariffs[$0] }
                let removedIDs = Set(removed.map(\.id))
                for tariff in removed { context.delete(tariff) }
                // Close the gap: the previous tariff runs on until the next remaining one.
                ValidityChain.relink(meter.tariffs.filter { !removedIDs.contains($0.id) })
                try? context.save()
            }
        }
        .navigationTitle("Tarife: \(meter.displayName)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddTariffSheet(meter: meter) }
    }
}

struct AddTariffSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meter: Meter

    @State private var priceText = ""
    @State private var baseFeeText = ""
    @State private var feedInText = ""
    @State private var validFrom: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Preise") {
                    HStack {
                        TextField("Preis pro \(meter.unitLabel)", text: $priceText)
                            .keyboardType(.decimalPad)
                        Text("€")
                    }
                    HStack {
                        TextField("Grundgebühr pro Monat", text: $baseFeeText)
                            .keyboardType(.decimalPad)
                        Text("€")
                    }
                    if meter.type == .electricityFeedIn {
                        HStack {
                            TextField("Einspeisevergütung pro \(meter.unitLabel)", text: $feedInText)
                                .keyboardType(.decimalPad)
                            Text("€")
                        }
                    }
                }
                Section {
                    DatePicker("Gültig ab", selection: $validFrom, displayedComponents: .date)
                } header: {
                    Text("Gültigkeit")
                } footer: {
                    Text("Der vorherige Tarif endet automatisch an diesem Tag. Ein Datum in der Zukunft legt den Tarif als geplant an.")
                }
            }
            .navigationTitle("Neuer Tarif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { save() }
                        .disabled(parseDecimal(priceText) == nil)
                }
            }
        }
    }

    private func parseDecimal(_ s: String) -> Decimal? {
        Formatting.parseDecimal(s)
    }

    private func save() {
        guard let price = parseDecimal(priceText) else { return }
        let base = parseDecimal(baseFeeText) ?? 0
        let feed = parseDecimal(feedInText)
        let t = Tariff(
            meter: meter,
            pricePerUnit: price,
            baseFeePerMonth: base,
            feedInPricePerUnit: feed,
            validFrom: validFrom
        )
        context.insert(t)
        let others = meter.tariffs.filter { $0.id != t.id }
        ValidityChain.relink(others + [t])
        try? context.save()
        dismiss()
    }
}
