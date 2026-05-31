import SwiftUI
import SwiftData
import Charts

struct MeterDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var meter: Meter

    @State private var showAddReading = false
    @State private var selectedGranularity: PeriodGranularity = .month

    private var calculator: ConsumptionCalculator { ConsumptionCalculator(meter: meter) }
    private var costCalculator: CostCalculator { CostCalculator(meter: meter) }
    private var sortedReadings: [Reading] { meter.readings.sorted { $0.date > $1.date } }
    private var accent: Color { Color(hex: meter.colorHex) ?? .accentColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summary
                miniChart
                readingsList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(meter.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddReading = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showAddReading) {
            AddReadingSheet(meter: meter)
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: meter.iconName)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(accent, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                if let bldg = meter.building {
                    Text(bldg.name).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(meter.type.localizedName).font(.headline)
                Text("Einheit: \(meter.unitLabel)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var summary: some View {
        let now = Date()
        let monthStart = PeriodGranularity.month.startDate(containing: now)
        let monthEnd = PeriodGranularity.month.endDate(after: monthStart)
        let yearStart = PeriodGranularity.year.startDate(containing: now)
        let monthPeriod = Period(granularity: .month, start: monthStart, end: monthEnd)
        let yearPeriod = Period(granularity: .year, start: yearStart, end: now)
        let monthCons = calculator.consumption(in: monthPeriod).amount
        let yearCons = calculator.consumption(in: yearPeriod).amount
        let forecast = Forecaster(meter: meter).yearForecast(asOf: now)

        VStack(spacing: 12) {
            HStack {
                statTile(title: "Aktueller Monat", value: Formatting.amount(monthCons, unit: meter.unitLabel))
                statTile(title: "Year-to-Date", value: Formatting.amount(yearCons, unit: meter.unitLabel))
            }
            if let f = forecast, f.projectedTotal > 0 {
                HStack {
                    statTile(title: "Prognose Jahr", value: Formatting.amount(f.projectedTotal, unit: meter.unitLabel))
                    statTile(title: "Kosten Monat", value: Formatting.currency(costCalculator.cost(in: monthPeriod).total))
                }
            }
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var miniChart: some View {
        let series: [ConsumptionResult] = {
            let calendar = Calendar.current
            let now = Date()
            let granularity: PeriodGranularity = selectedGranularity
            let count: Int = switch granularity {
                case .day: 30
                case .week: 12
                case .month: 12
                case .quarter: 8
                case .year: 5
            }
            let component: Calendar.Component = switch granularity {
                case .day: .day
                case .week: .weekOfYear
                case .month: .month
                case .quarter: .month
                case .year: .year
            }
            let value: Int = switch granularity {
                case .quarter: -count * 3
                default: -count
            }
            let end = granularity.endDate(after: granularity.startDate(containing: now))
            let start = calendar.date(byAdding: component, value: value, to: end) ?? now
            return calculator.series(granularity: granularity, from: start, to: end)
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Verlauf").font(.headline)
                Spacer()
                Picker("", selection: $selectedGranularity) {
                    ForEach(PeriodGranularity.allCases) { g in
                        Text(g.localizedName).tag(g)
                    }
                }
                .pickerStyle(.menu)
            }
            Chart(series, id: \.period) { item in
                BarMark(
                    x: .value("Periode", item.period.start),
                    y: .value("Verbrauch", item.amount.doubleValue)
                )
                .foregroundStyle(accent.opacity(item.isPartial ? 0.4 : 0.9))
            }
            .frame(height: 180)
        }
        .padding(Theme.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    @ViewBuilder private var readingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ablesungen").font(.headline)
            if sortedReadings.isEmpty {
                Text("Noch keine Ablesungen erfasst.").foregroundStyle(.secondary).italic()
            } else {
                ForEach(sortedReadings) { reading in
                    ReadingRow(reading: reading, unit: meter.unitLabel)
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(reading)
                                try? context.save()
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }
}

struct ReadingRow: View {
    let reading: Reading
    let unit: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatting.date.string(from: reading.date))
                    .font(.subheadline.weight(.medium))
                if let note = reading.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Formatting.counter(reading.value, unit: unit))
                .font(.subheadline)
                .monospacedDigit()
            if reading.photoData != nil {
                Image(systemName: "photo.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
