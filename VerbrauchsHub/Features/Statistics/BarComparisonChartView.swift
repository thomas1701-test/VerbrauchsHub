import SwiftUI
import Charts

struct BarComparisonChartView: View {
    let meters: [Meter]
    let granularity: PeriodGranularity
    let start: Date
    let end: Date

    private struct Bar: Identifiable {
        let id = UUID()
        let meterName: String
        let color: Color
        let periodStart: Date
        let label: String
        let amount: Double
        let isPartial: Bool
    }

    private var bars: [Bar] {
        var result: [Bar] = []
        for meter in meters {
            let calc = ConsumptionCalculator(meter: meter)
            let color = Color(hex: meter.colorHex) ?? .accentColor
            for item in calc.series(granularity: granularity, from: start, to: end) {
                result.append(.init(
                    meterName: meter.displayName,
                    color: color,
                    periodStart: item.period.start,
                    label: item.period.displayLabel,
                    amount: item.amount.doubleValue,
                    isPartial: item.isPartial
                ))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Periodenvergleich").font(.headline)
            Chart(bars) { b in
                BarMark(
                    x: .value("Periode", b.label),
                    y: .value("Verbrauch", b.amount)
                )
                .foregroundStyle(by: .value("Zähler", b.meterName))
                .opacity(b.isPartial ? 0.5 : 1.0)
                .position(by: .value("Zähler", b.meterName))
            }
            .chartForegroundStyleScale(domain: meters.map(\.displayName), range: meters.map { Color(hex: $0.colorHex) ?? .accentColor })
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}
