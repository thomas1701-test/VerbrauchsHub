import SwiftUI
import Charts

struct LineChartView: View {
    let meters: [Meter]
    let granularity: PeriodGranularity
    let start: Date
    let end: Date
    let comparison: ComparisonMode

    private struct DataPoint: Identifiable {
        let id = UUID()
        let meterID: UUID
        let meterName: String
        let color: Color
        let date: Date
        let value: Double
        let isPartial: Bool
        let series: String // "Aktuell" or "Vergleich"
    }

    private var dataPoints: [DataPoint] {
        var points: [DataPoint] = []
        for meter in meters {
            let calc = ConsumptionCalculator(meter: meter)
            let color = Color(hex: meter.colorHex) ?? .accentColor
            let series = calc.series(granularity: granularity, from: start, to: end)
            for item in series {
                points.append(.init(
                    meterID: meter.id,
                    meterName: meter.displayName,
                    color: color,
                    date: item.period.start,
                    value: item.amount.doubleValue,
                    isPartial: item.isPartial,
                    series: "Aktuell"
                ))
            }
            if comparison != .none {
                let (compStart, compEnd) = comparisonRange()
                let comp = calc.series(granularity: granularity, from: compStart, to: compEnd)
                let offset = end.timeIntervalSince(compEnd)
                for item in comp {
                    points.append(.init(
                        meterID: meter.id,
                        meterName: meter.displayName,
                        color: color,
                        date: item.period.start.addingTimeInterval(offset),
                        value: item.amount.doubleValue,
                        isPartial: item.isPartial,
                        series: "Vergleich"
                    ))
                }
            }
        }
        return points
    }

    private func comparisonRange() -> (Date, Date) {
        let calendar = Calendar.current
        switch comparison {
        case .none:
            return (start, end)
        case .previousPeriod:
            let interval = end.timeIntervalSince(start)
            return (start.addingTimeInterval(-interval), start)
        case .previousYear:
            let prevStart = calendar.date(byAdding: .year, value: -1, to: start) ?? start
            let prevEnd = calendar.date(byAdding: .year, value: -1, to: end) ?? end
            return (prevStart, prevEnd)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Verbrauch über Zeit").font(.headline)
            Chart(dataPoints) { p in
                LineMark(
                    x: .value("Datum", p.date),
                    y: .value("Verbrauch", p.value)
                )
                .foregroundStyle(by: .value("Zähler", p.meterName))
                .lineStyle(StrokeStyle(lineWidth: p.series == "Aktuell" ? 2 : 1.5, dash: p.series == "Vergleich" ? [4, 4] : (p.isPartial ? [2, 3] : [])))
                .symbol(by: .value("Zähler", p.meterName))
            }
            .chartForegroundStyleScale(domain: meters.map(\.displayName), range: meters.map { Color(hex: $0.colorHex) ?? .accentColor })
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}
