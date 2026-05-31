import SwiftUI
import Charts

struct MeterSummaryCard: View {
    let meter: Meter

    private var calculator: ConsumptionCalculator { ConsumptionCalculator(meter: meter) }
    private var costCalculator: CostCalculator { CostCalculator(meter: meter) }

    private var currentMonth: Period {
        let now = Date()
        let start = PeriodGranularity.month.startDate(containing: now)
        let end = PeriodGranularity.month.endDate(after: start)
        return Period(granularity: .month, start: start, end: end)
    }

    private var previousMonth: Period {
        let start = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth.start) ?? currentMonth.start
        let end = currentMonth.start
        return Period(granularity: .month, start: start, end: end)
    }

    private var currentConsumption: ConsumptionResult { calculator.consumption(in: currentMonth) }
    private var previousConsumption: ConsumptionResult { calculator.consumption(in: previousMonth) }

    private var trend: TrendResult {
        TrendResult(current: currentConsumption.amount, previous: previousConsumption.amount)
    }

    private var monthCost: CostResult { costCalculator.cost(in: currentMonth) }

    private var sparkData: [ConsumptionResult] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .month, value: -11, to: currentMonth.start) else { return [] }
        return calculator.series(granularity: .month, from: start, to: currentMonth.end)
    }

    private var accent: Color { Color(hex: meter.colorHex) ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: meter.iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(accent, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meter.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if let bldg = meter.building {
                        Text(bldg.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trendBadge
            }

            HStack(alignment: .lastTextBaseline) {
                Text(Formatting.amount(currentConsumption.amount, unit: meter.unitLabel))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                if currentConsumption.isPartial {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                if monthCost.total != 0 {
                    Text(Formatting.currency(monthCost.total))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !sparkData.isEmpty {
                Chart(sparkData, id: \.period) { item in
                    BarMark(
                        x: .value("Monat", item.period.start, unit: .month),
                        y: .value("Verbrauch", item.amount.doubleValue)
                    )
                    .foregroundStyle(accent.opacity(item.isPartial ? 0.4 : 0.85))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 40)
            }
        }
        .padding(Theme.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    @ViewBuilder private var trendBadge: some View {
        if let pct = trend.deltaPercent {
            let icon: String = {
                switch trend.direction {
                case .up: return "arrow.up.right"
                case .down: return "arrow.down.right"
                case .flat: return "arrow.right"
                }
            }()
            let color: Color = {
                // For most meters down is good, for feedIn up is good.
                let isGood = meter.type.isFeedIn ? (trend.direction == .up) : (trend.direction == .down)
                if trend.direction == .flat { return .secondary }
                return isGood ? .green : .red
            }()
            HStack(spacing: 2) {
                Image(systemName: icon)
                let value = abs(pct.doubleValue)
                Text(String(format: "%.0f%%", value))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
        }
    }
}
