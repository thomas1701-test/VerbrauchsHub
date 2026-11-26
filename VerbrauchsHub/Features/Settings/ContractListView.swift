import SwiftUI
import SwiftData

struct ContractOverviewView: View {
    @Query(sort: \Meter.createdAt) private var meters: [Meter]

    var body: some View {
        List {
            ForEach(meters) { meter in
                NavigationLink {
                    ContractListView(meter: meter)
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
                        Text("\(meter.contracts.count + meter.tariffs.filter { $0.contract == nil }.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Verträge")
    }
}

/// Contracts of one meter with their prices, plus prices without a contract (data from 1.1).
struct ContractListView: View {
    @Environment(\.modelContext) private var context
    @Bindable var meter: Meter

    @State private var showNewContract = false
    @State private var showNewTariff = false
    @State private var editingContract: Contract?
    @State private var editingTariff: Tariff?

    private var sortedContracts: [Contract] {
        meter.contracts.sorted { firstStart($0) > firstStart($1) }
    }

    private var looseTariffs: [Tariff] {
        meter.tariffs.filter { $0.contract == nil }.sorted { $0.validFrom > $1.validFrom }
    }

    var body: some View {
        List {
            ForEach(sortedContracts) { contract in
                Section {
                    Button { editingContract = contract } label: {
                        ContractHeader(contract: contract)
                    }
                    .buttonStyle(.plain)
                    ForEach(contract.tariffs.sorted { $0.validFrom > $1.validFrom }) { tariff in
                        Button { editingTariff = tariff } label: {
                            TariffRow(tariff: tariff, unitLabel: meter.unitLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !looseTariffs.isEmpty {
                Section("Preise ohne Vertrag") {
                    ForEach(looseTariffs) { tariff in
                        Button { editingTariff = tariff } label: {
                            TariffRow(tariff: tariff, unitLabel: meter.unitLabel)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteLooseTariffs)
                }
            }
        }
        .overlay {
            if meter.contracts.isEmpty && meter.tariffs.isEmpty {
                ContentUnavailableView(
                    "Noch kein Vertrag",
                    systemImage: "doc.text",
                    description: Text("Lege deinen Vertrag mit Preis an, damit VerbrauchsHub Kosten berechnet und dich an die Kündigungsfrist erinnert.")
                )
            }
        }
        .navigationTitle(meter.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Neuer Vertrag", systemImage: "doc.badge.plus") { showNewContract = true }
                    Button("Neuer Preis ohne Vertrag", systemImage: "eurosign") { showNewTariff = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewContract) { ContractFormSheet(meter: meter) }
        .sheet(isPresented: $showNewTariff) { TariffFormSheet(meter: meter) }
        .sheet(item: $editingContract) { ContractFormSheet(meter: meter, contract: $0) }
        .sheet(item: $editingTariff) { TariffFormSheet(meter: meter, contract: $0.contract, tariff: $0) }
    }

    private func firstStart(_ contract: Contract) -> Date {
        contract.tariffs.map(\.validFrom).min() ?? contract.startDate
    }

    private func deleteLooseTariffs(_ offsets: IndexSet) {
        let removed = offsets.map { looseTariffs[$0] }
        let removedIDs = Set(removed.map(\.id))
        for tariff in removed { context.delete(tariff) }
        // Close the gap: the previous tariff runs on until the next remaining one.
        ValidityChain.relink(meter.tariffs.filter { !removedIDs.contains($0.id) })
        try? context.save()
    }
}

private struct ContractHeader: View {
    let contract: Contract

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(contract.provider).font(.headline)
                Spacer()
                ValidityBadge(status: contract.status(on: .now))
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Text(contract.cancellationText(asOf: .now)).font(.caption).foregroundStyle(.secondary)
            if let guarantee = contract.priceGuaranteeUntil {
                Text("Preisgarantie bis \(Formatting.date.string(from: guarantee))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

struct TariffRow: View {
    let tariff: Tariff
    let unitLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatting.currency(tariff.pricePerUnit) + "/\(unitLabel)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ValidityBadge(status: tariff.status(on: .now))
            }
            if tariff.baseFeePerMonth != 0 {
                Text("Grundgebühr: \(Formatting.currency(tariff.baseFeePerMonth))/Monat").font(.caption).foregroundStyle(.secondary)
            }
            if let feed = tariff.feedInPricePerUnit {
                Text("Einspeisung: \(Formatting.currency(feed))/\(unitLabel)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Gültig ab: \(Formatting.date.string(from: tariff.validFrom))" + (tariff.validTo.map { " bis \(Formatting.date.string(from: $0))" } ?? ""))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

extension Contract {
    func cancellationText(asOf now: Date) -> String {
        switch cancellation(asOf: now) {
        case .deadline(let date, _):
            "Kündbar bis \(Formatting.date.string(from: date))"
        case .anytime(let value, let unit):
            "Kündbar mit \(value) \(unit.label(value)) Frist"
        case nil:
            "Kündigungsfrist nicht hinterlegt"
        }
    }
}
