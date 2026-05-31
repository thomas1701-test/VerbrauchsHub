import SwiftUI
import SwiftData
import Charts

enum ComparisonMode: String, CaseIterable, Identifiable {
    case none, previousPeriod, previousYear
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Kein Vergleich"
        case .previousPeriod: return "Vorperiode"
        case .previousYear: return "Vorjahr"
        }
    }
}

struct StatisticsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Meter.createdAt) private var allMeters: [Meter]

    @State private var granularity: PeriodGranularity = .month
    @State private var comparison: ComparisonMode = .none
    @State private var selectedMeterIDs: Set<UUID> = []
    @State private var showMeterPicker = false

    private var visibleMeters: [Meter] {
        if let id = appState.selectedBuildingID {
            return allMeters.filter { $0.building?.id == id }
        }
        return allMeters
    }

    private var activeMeters: [Meter] {
        if selectedMeterIDs.isEmpty { return visibleMeters }
        return visibleMeters.filter { selectedMeterIDs.contains($0.id) }
    }

    private var rangeStart: Date {
        let calendar = Calendar.current
        let now = Date()
        let end = granularity.endDate(after: granularity.startDate(containing: now))
        switch granularity {
        case .day: return calendar.date(byAdding: .day, value: -30, to: end) ?? now
        case .week: return calendar.date(byAdding: .weekOfYear, value: -12, to: end) ?? now
        case .month: return calendar.date(byAdding: .month, value: -12, to: end) ?? now
        case .quarter: return calendar.date(byAdding: .month, value: -24, to: end) ?? now
        case .year: return calendar.date(byAdding: .year, value: -5, to: end) ?? now
        }
    }

    private var rangeEnd: Date {
        granularity.endDate(after: granularity.startDate(containing: Date()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    if activeMeters.isEmpty {
                        ContentUnavailableView("Keine Zähler",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Lege Zähler an, um Statistiken zu sehen."))
                            .padding(.top, 60)
                    } else {
                        LineChartView(meters: activeMeters, granularity: granularity, start: rangeStart, end: rangeEnd, comparison: comparison)
                            .frame(height: 280)
                            .padding(Theme.cardPadding)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

                        BarComparisonChartView(meters: activeMeters, granularity: granularity, start: rangeStart, end: rangeEnd)
                            .frame(height: 260)
                            .padding(Theme.cardPadding)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

                        if hasPV() {
                            EnergyBalanceChartView(meters: visibleMeters, granularity: granularity, start: rangeStart, end: rangeEnd)
                                .frame(height: 260)
                                .padding(Theme.cardPadding)
                                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        }

                        TotalsTable(meters: activeMeters, granularity: granularity, start: rangeStart, end: rangeEnd)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Statistik")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BuildingSwitcher()
                }
            }
            .sheet(isPresented: $showMeterPicker) {
                MeterFilterSheet(meters: visibleMeters, selected: $selectedMeterIDs)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 10) {
            Picker("Periode", selection: $granularity) {
                ForEach(PeriodGranularity.allCases) { g in
                    Text(g.localizedName).tag(g)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Vergleich", selection: $comparison) {
                    ForEach(ComparisonMode.allCases) { c in
                        Text(c.label).tag(c)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button {
                    showMeterPicker = true
                } label: {
                    Label(filterLabel(), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private func filterLabel() -> String {
        if selectedMeterIDs.isEmpty { return "Alle Zähler" }
        return "\(selectedMeterIDs.count) ausgewählt"
    }

    private func hasPV() -> Bool {
        visibleMeters.contains { $0.type == .electricityFeedIn }
    }
}

struct MeterFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meters: [Meter]
    @Binding var selected: Set<UUID>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Alle auswählen") { selected = Set(meters.map { $0.id }) }
                    Button("Alle abwählen") { selected.removeAll() }
                }
                Section {
                    ForEach(meters) { meter in
                        HStack {
                            Image(systemName: meter.iconName)
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color(hex: meter.colorHex) ?? .accentColor, in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) {
                                Text(meter.displayName)
                                if let bldg = meter.building {
                                    Text(bldg.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selected.contains(meter.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(meter.id) { selected.remove(meter.id) }
                            else { selected.insert(meter.id) }
                        }
                    }
                }
            }
            .navigationTitle("Zähler filtern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

struct TotalsTable: View {
    let meters: [Meter]
    let granularity: PeriodGranularity
    let start: Date
    let end: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summen im Zeitraum").font(.headline)
            ForEach(meters) { meter in
                let total = ConsumptionCalculator(meter: meter)
                    .totalConsumption(from: start, to: end).amount
                let cost = CostCalculator(meter: meter)
                    .cost(in: Period(granularity: .day, start: start, end: end))
                HStack {
                    Image(systemName: meter.iconName)
                        .foregroundStyle(Color(hex: meter.colorHex) ?? .accentColor)
                    Text(meter.displayName)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatting.amount(total, unit: meter.unitLabel))
                            .font(.subheadline.weight(.medium))
                        if cost.total != 0 {
                            Text(Formatting.currency(cost.total))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }
        }
        .padding(Theme.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }
}
