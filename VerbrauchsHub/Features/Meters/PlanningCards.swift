import SwiftUI

/// Annual goal and billing forecast on the meter detail page.
struct PlanningCards: View {
    let meter: Meter
    let accent: Color
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let target = meter.annualTarget {
                GoalCard(meter: meter, target: target, accent: accent)
            }
            if meter.advancePaymentPerMonth != nil {
                BillingCard(meter: meter)
            }
            if meter.annualTarget == nil && meter.advancePaymentPerMonth == nil {
                Button(action: onEdit) {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.title3)
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meter.type.isFeedIn ? "Jahresziel festlegen" : "Abschlag & Jahresziel festlegen")
                                .font(.subheadline.weight(.semibold))
                            Text(meter.type.isFeedIn ? "Sieh, ob deine Anlage das Ziel erreicht." : "Erfahre früh, ob eine Nachzahlung droht.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(Theme.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GoalCard: View {
    let meter: Meter
    let target: Decimal
    let accent: Color

    var body: some View {
        let forecast = Forecaster(meter: meter).yearForecast()
        let yearToDate = forecast?.yearToDate ?? 0
        let projected = forecast?.projectedTotal ?? 0
        let progress = min(1, max(0, (yearToDate / target).doubleValue))
        // For PV feed-in more is better.
        let higherIsBetter = meter.type.isFeedIn
        let deviation = projected > 0 ? ((projected - target) / target * 100).doubleValue : nil
        let onTrack = deviation.map { higherIsBetter ? $0 >= 0 : $0 <= 0 }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Jahresziel \(Calendar.current.component(.year, from: .now).formatted(.number.grouping(.never)))", systemImage: "target")
                    .font(.headline)
                Spacer()
                Text(Formatting.amount(target, unit: meter.unitLabel, fractionDigits: 0))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(onTrack == false ? .orange : accent)
            HStack {
                Text("Bisher \(Formatting.amount(yearToDate, unit: meter.unitLabel, fractionDigits: 0))")
                Spacer()
                Text("\(Int((progress * 100).rounded())) %")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let deviation, let onTrack {
                Label {
                    Text(goalText(projected: projected, deviation: deviation))
                } icon: {
                    Image(systemName: onTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(onTrack ? .green : .orange)
                }
                .font(.subheadline)
            } else {
                Text("Für eine Prognose braucht es Ablesungen über mindestens zwei Wochen in diesem Jahr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    private func goalText(projected: Decimal, deviation: Double) -> String {
        let amount = Formatting.amount(projected, unit: meter.unitLabel, fractionDigits: 0)
        let percent = Int(abs(deviation).rounded())
        if percent == 0 { return "Prognose \(amount) – genau im Ziel" }
        let direction = deviation > 0 ? "über" : "unter"
        return "Prognose \(amount) – \(percent) % \(direction) dem Ziel"
    }
}

private struct BillingCard: View {
    let meter: Meter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Jahresabrechnung", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            if let forecast = BillingForecaster.forecast(for: meter) {
                content(forecast)
            } else {
                Text(missingReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    @ViewBuilder
    private func content(_ forecast: BillingForecast) -> some View {
        let lastDay = forecast.periodEnd.addingTimeInterval(-86_400)
        Text("\(Formatting.date.string(from: forecast.periodStart)) – \(Formatting.date.string(from: lastDay))")
            .font(.caption)
            .foregroundStyle(.secondary)

        VStack(spacing: 6) {
            row("Voraussichtliche Kosten", Formatting.currency(forecast.projectedCost))
            row("Abschläge (12 ×)", Formatting.currency(forecast.advancePayments))
        }
        .font(.subheadline)

        let balance = forecast.balance
        let isRefund = balance < 0
        HStack {
            Image(systemName: isRefund ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(isRefund ? .green : .orange)
            Text(isRefund ? "Voraussichtliche Erstattung" : "Voraussichtliche Nachzahlung")
            Spacer()
            Text(Formatting.currency(abs(balance)))
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))

        if let advance = meter.advancePaymentPerMonth, abs(forecast.suggestedAdvance - advance) >= 1 {
            Text("Passender Abschlag: \(Formatting.currency(forecast.suggestedAdvance)) pro Monat (aktuell \(Formatting.currency(advance))).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Text(forecast.usesPreviousYear
             ? "Hochgerechnet mit dem Verlauf des Vorjahres und den hinterlegten Tarifen, auch künftigen."
             : "Gleichmäßig hochgerechnet mit den hinterlegten Tarifen, auch künftigen. Mit Ablesungen aus dem Vorjahr wird die Prognose genauer.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private var missingReason: String {
        if meter.tariffs.isEmpty {
            return "Lege unter Einstellungen › Tarife einen Tarif für diesen Zähler an, um die Abrechnung vorherzusagen."
        }
        return "Für eine Prognose braucht es Ablesungen über mindestens zwei Wochen im aktuellen Abrechnungsjahr."
    }
}
