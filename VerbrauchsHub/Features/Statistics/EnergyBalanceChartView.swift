import SwiftUI
import Charts

struct EnergyBalanceChartView: View {
    let meters: [Meter]
    let granularity: PeriodGranularity
    let start: Date
    let end: Date

    private struct Layer: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let value: Double
    }

    private var data: [Layer] {
        var layers: [Layer] = []
        let purchase = meters.first { $0.type == .electricity }
        let feedIn = meters.first { $0.type == .electricityFeedIn }
        let selfCons = meters.first { $0.type == .electricitySelfConsumption }

        let purchaseSeries = purchase.map { ConsumptionCalculator(meter: $0).series(granularity: granularity, from: start, to: end) } ?? []
        let feedInSeries = feedIn.map { ConsumptionCalculator(meter: $0).series(granularity: granularity, from: start, to: end) } ?? []
        let selfConsSeries = selfCons.map { ConsumptionCalculator(meter: $0).series(granularity: granularity, from: start, to: end) } ?? []

        let dates = Set(purchaseSeries.map(\.period.start) + feedInSeries.map(\.period.start) + selfConsSeries.map(\.period.start)).sorted()
        for date in dates {
            if let p = purchaseSeries.first(where: { $0.period.start == date }) {
                layers.append(.init(date: date, category: "Netzbezug", value: p.amount.doubleValue))
            }
            if let f = feedInSeries.first(where: { $0.period.start == date }) {
                layers.append(.init(date: date, category: "Einspeisung", value: f.amount.doubleValue))
            }
            if let s = selfConsSeries.first(where: { $0.period.start == date }) {
                layers.append(.init(date: date, category: "Eigenverbrauch", value: s.amount.doubleValue))
            }
        }
        return layers
    }

    var autarkyText: String? {
        let purchase = meters.first { $0.type == .electricity }
        let selfCons = meters.first { $0.type == .electricitySelfConsumption }
        guard let purchase, let selfCons else { return nil }
        let p = ConsumptionCalculator(meter: purchase).totalConsumption(from: start, to: end).amount
        let s = ConsumptionCalculator(meter: selfCons).totalConsumption(from: start, to: end).amount
        guard p + s > 0 else { return nil }
        let autarky = (s / (p + s) * 100)
        return "Autarkiegrad: \(Formatting.percent(autarky))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PV-Energiebilanz").font(.headline)
                Spacer()
                if let t = autarkyText {
                    Text(t).font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart(data) { layer in
                AreaMark(
                    x: .value("Datum", layer.date),
                    y: .value("kWh", layer.value)
                )
                .foregroundStyle(by: .value("Kategorie", layer.category))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                "Netzbezug": Color.orange,
                "Einspeisung": Color.green,
                "Eigenverbrauch": Color.blue
            ])
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}
