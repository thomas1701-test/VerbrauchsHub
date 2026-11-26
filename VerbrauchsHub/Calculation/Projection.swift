import Foundation

/// Consumption of a period (calendar year, billing year) projected to its end.
struct PeriodProjection: Hashable {
    /// Measured consumption inside the period.
    let actual: Decimal
    /// Expected consumption for the whole period.
    let total: Decimal
    /// Span inside the period that is covered by readings.
    let coveredStart: Date
    let coveredEnd: Date
    /// True if the seasonal pattern of the previous year was used instead of a straight line.
    let usesPreviousYear: Bool
}

extension ConsumptionCalculator {
    /// Minimum covered span before a projection is shown – a few days of data would scale wildly.
    static let minimumProjectionCoverage: TimeInterval = 14 * 24 * 60 * 60

    /// Projects the consumption of `[start, end)` from the readings up to `now`.
    ///
    /// If the readings also cover the same period one year earlier, the measured part is scaled
    /// with last year's distribution (heating and gas depend strongly on the season); otherwise
    /// the average daily rate is extrapolated.
    func projection(from start: Date, to end: Date, asOf now: Date, calendar: Calendar = .current) -> PeriodProjection? {
        guard let first = sortedReadings.first?.date, let last = sortedReadings.last?.date, sortedReadings.count >= 2 else {
            return nil
        }
        let coveredStart = max(start, first)
        let coveredEnd = min(now, last, end)
        guard coveredEnd > coveredStart else { return nil }

        let measured = totalConsumption(from: coveredStart, to: coveredEnd, calendar: calendar)
        guard measured.coveredSeconds >= Self.minimumProjectionCoverage else { return nil }

        if let prevStart = calendar.date(byAdding: .year, value: -1, to: start),
           let prevEnd = calendar.date(byAdding: .year, value: -1, to: end),
           let prevCoveredStart = calendar.date(byAdding: .year, value: -1, to: coveredStart),
           let prevCoveredEnd = calendar.date(byAdding: .year, value: -1, to: coveredEnd),
           first <= prevStart, last >= prevEnd {
            let prevTotal = totalConsumption(from: prevStart, to: prevEnd, calendar: calendar).amount
            let prevCovered = totalConsumption(from: prevCoveredStart, to: prevCoveredEnd, calendar: calendar).amount
            if prevCovered > 0, prevTotal > 0 {
                return PeriodProjection(
                    actual: measured.amount,
                    total: measured.amount * prevTotal / prevCovered,
                    coveredStart: coveredStart,
                    coveredEnd: coveredEnd,
                    usesPreviousYear: true
                )
            }
        }

        let factor = Decimal(end.timeIntervalSince(start) / measured.coveredSeconds)
        return PeriodProjection(
            actual: measured.amount,
            total: measured.amount * factor,
            coveredStart: coveredStart,
            coveredEnd: coveredEnd,
            usesPreviousYear: false
        )
    }
}

/// Expected annual bill compared with the advance payments (Abschläge).
struct BillingForecast: Hashable {
    let periodStart: Date
    let periodEnd: Date
    let projectedConsumption: Decimal
    let projectedCost: Decimal
    /// Advance payments for the whole period (12 × monthly advance).
    let advancePayments: Decimal
    /// Positive: additional payment due. Negative: refund.
    var balance: Decimal { projectedCost - advancePayments }
    /// Monthly advance that would cover the projected cost, rounded up to whole euros.
    var suggestedAdvance: Decimal {
        var monthly = projectedCost / 12
        var rounded = Decimal()
        NSDecimalRound(&rounded, &monthly, 0, .up)
        return rounded
    }
    let usesPreviousYear: Bool
}

enum BillingForecaster {
    /// The billing period (one year) that contains `date`, repeating yearly from `anchor`.
    static func period(anchor: Date, containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        var start = calendar.startOfDay(for: anchor)
        while start > date, let previous = calendar.date(byAdding: .year, value: -1, to: start) { start = previous }
        while let next = calendar.date(byAdding: .year, value: 1, to: start), next <= date { start = next }
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return (start, end)
    }

    static func forecast(for meter: Meter, asOf now: Date = .now, calendar: Calendar = .current) -> BillingForecast? {
        guard !meter.type.isFeedIn,
              let advance = meter.advancePaymentPerMonth, advance > 0,
              let anchor = meter.billingStartDate else { return nil }
        let costs = CostCalculator(meter: meter)
        guard !costs.tariffs.isEmpty else { return nil }

        let (start, end) = period(anchor: anchor, containing: now, calendar: calendar)
        guard let projection = costs.consumption.projection(from: start, to: end, asOf: now, calendar: calendar) else {
            return nil
        }

        // Measured part with the tariffs that actually applied, the rest with the tariffs
        // stored for the remaining time (including contracts that only start later).
        let measuredPeriod = Period(granularity: .day, start: start, end: projection.coveredEnd)
        let measuredCost = costs.cost(in: measuredPeriod, calendar: calendar).total
        let remainingConsumption = max(0, projection.total - projection.actual)
        let remainingCost = self.remainingCost(
            costs: costs,
            consumption: remainingConsumption,
            from: projection.coveredEnd,
            to: end,
            seasonal: projection.usesPreviousYear,
            calendar: calendar
        )

        return BillingForecast(
            periodStart: start,
            periodEnd: end,
            projectedConsumption: projection.total,
            projectedCost: measuredCost + remainingCost,
            advancePayments: advance * 12,
            usesPreviousYear: projection.usesPreviousYear
        )
    }

    /// Cost of the not yet measured `[from, to)`, split at every tariff change.
    ///
    /// The expected consumption is spread over the segments by time, or with last year's
    /// distribution for seasonal projections (heating in winter costs more after a price rise in
    /// January than a straight line suggests).
    private static func remainingCost(
        costs: CostCalculator,
        consumption: Decimal,
        from: Date,
        to: Date,
        seasonal: Bool,
        calendar: Calendar
    ) -> Decimal {
        guard to > from, let fallback = costs.activeTariff(on: from) ?? costs.tariffs.last(where: { $0.validFrom <= from }) ?? costs.tariffs.first else {
            return 0
        }

        let changes = costs.tariffs.flatMap { [$0.validFrom, $0.validTo].compactMap { $0 } }
            .filter { $0 > from && $0 < to }
        let bounds = ([from] + Set(changes).sorted() + [to])
        let segments = zip(bounds, bounds.dropFirst()).map { (start: $0, end: $1) }

        let secondsPerMonth: Double = 86_400 * 30.4375
        let timeWeights = segments.map { Decimal($0.end.timeIntervalSince($0.start)) }
        var weights = timeWeights
        if seasonal {
            let previous = segments.map { segment -> Decimal in
                guard let prevStart = calendar.date(byAdding: .year, value: -1, to: segment.start),
                      let prevEnd = calendar.date(byAdding: .year, value: -1, to: segment.end) else { return 0 }
                return costs.consumption.totalConsumption(from: prevStart, to: prevEnd, calendar: calendar).amount
            }
            if previous.reduce(0, +) > 0 { weights = previous }
        }
        let totalWeight = weights.reduce(0, +)

        var cost: Decimal = 0
        for (index, segment) in segments.enumerated() {
            let tariff = costs.activeTariff(on: segment.start) ?? fallback
            let share = totalWeight > 0 ? consumption * weights[index] / totalWeight : 0
            let months = Decimal(segment.end.timeIntervalSince(segment.start) / secondsPerMonth)
            cost += share * tariff.pricePerUnit + months * tariff.baseFeePerMonth
        }
        return cost
    }
}
