import Foundation

/// Pure value type representing the consumption of a meter for a given period.
struct ConsumptionResult: Hashable {
    let period: Period
    let amount: Decimal
    /// True if the period is only partially covered by real readings.
    let isPartial: Bool
    /// True if no reading data exists for any part of the period.
    var isEmpty: Bool { amount == 0 && isPartial == false && !hasCoverage }
    let hasCoverage: Bool
}

/// Computes consumption per period using linear interpolation between cumulative meter readings.
struct ConsumptionCalculator {
    /// Sorted readings (ascending by date). Pass the result of `meter.readings.sorted`.
    let sortedReadings: [Reading]

    init(meter: Meter) {
        self.sortedReadings = meter.readings.sorted { $0.date < $1.date }
    }

    init(readings: [Reading]) {
        self.sortedReadings = readings.sorted { $0.date < $1.date }
    }

    /// Consumption for a single closed period `[period.start, period.end)`.
    func consumption(in period: Period, calendar: Calendar = .current) -> ConsumptionResult {
        guard sortedReadings.count >= 2 else {
            return ConsumptionResult(period: period, amount: 0, isPartial: false, hasCoverage: false)
        }

        // Earliest and latest reading dates
        guard let firstDate = sortedReadings.first?.date,
              let lastDate = sortedReadings.last?.date else {
            return ConsumptionResult(period: period, amount: 0, isPartial: false, hasCoverage: false)
        }

        // No overlap at all
        if period.end <= firstDate || period.start >= lastDate {
            return ConsumptionResult(period: period, amount: 0, isPartial: false, hasCoverage: false)
        }

        var total: Decimal = 0
        var partial = false

        // Effective range clipped to covered span
        let coveredStart = max(period.start, firstDate)
        let coveredEnd = min(period.end, lastDate)
        if coveredStart > period.start || coveredEnd < period.end {
            partial = true
        }

        // Iterate consecutive reading pairs and sum their contribution to the period.
        for i in 0..<(sortedReadings.count - 1) {
            let a = sortedReadings[i]
            let b = sortedReadings[i + 1]
            if b.date <= coveredStart { continue }
            if a.date >= coveredEnd { break }

            let delta = b.value - a.value
            if delta <= 0 { continue } // ignore meter resets/decreases

            let pairSeconds: Double = b.date.timeIntervalSince(a.date)
            guard pairSeconds > 0 else { continue }

            let overlapStart = max(a.date, coveredStart)
            let overlapEnd = min(b.date, coveredEnd)
            let overlapSeconds: Double = overlapEnd.timeIntervalSince(overlapStart)
            if overlapSeconds <= 0 { continue }

            let ratioDouble: Double = overlapSeconds / pairSeconds
            let ratio = Decimal(ratioDouble)
            total += delta * ratio
        }

        return ConsumptionResult(period: period, amount: total, isPartial: partial, hasCoverage: true)
    }

    /// Consumption per period for a granularity over a range.
    func series(granularity: PeriodGranularity, from start: Date, to end: Date, calendar: Calendar = .current) -> [ConsumptionResult] {
        granularity.periods(from: start, to: end, calendar: calendar).map { consumption(in: $0, calendar: calendar) }
    }

    /// Total consumption between any two dates (linear-interpolated).
    func totalConsumption(from start: Date, to end: Date, calendar: Calendar = .current) -> ConsumptionResult {
        let period = Period(granularity: .day, start: start, end: end)
        return consumption(in: period, calendar: calendar)
    }

}
