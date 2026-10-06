import Foundation

/// Plausibility check for a new reading before it is saved.
enum ReadingCheck: Equatable {
    /// Lower than the reading before – typo or meter exchange.
    case lowerThanPrevious(previous: Decimal)
    /// Daily consumption since the last reading is far above the usual rate.
    case unusuallyHigh(factor: Int)

    /// How many times the usual daily rate counts as suspicious.
    static let highFactor: Double = 3

    /// - Parameter readings: existing readings of the meter (any order); `editing` is ignored.
    static func evaluate(value: Decimal, date: Date, readings: [Reading], editing: Reading? = nil) -> ReadingCheck? {
        let others = readings.filter { $0 !== editing }.sorted { $0.date < $1.date }
        guard let previous = others.last(where: { $0.date <= date }) else { return nil }
        if value < previous.value { return .lowerThanPrevious(previous: previous.value) }

        // Usual rate: the year before the previous reading (at least three readings needed).
        let history = others.filter { $0.date <= previous.date }
        guard history.count >= 3, let oldest = history.first(where: {
            $0.date >= previous.date.addingTimeInterval(-365 * 86_400)
        }) ?? history.first, oldest !== previous else { return nil }

        let historyDays = previous.date.timeIntervalSince(oldest.date) / 86_400
        let historyAmount = (previous.value - oldest.value).doubleValue
        guard historyDays >= 14, historyAmount > 0 else { return nil }
        let usualRate = historyAmount / historyDays

        // Short gaps make the daily rate jumpy, so compare over at least one day.
        let days = max(1, date.timeIntervalSince(previous.date) / 86_400)
        let rate = (value - previous.value).doubleValue / days
        let factor = rate / usualRate
        return factor >= highFactor ? .unusuallyHigh(factor: Int(factor.rounded())) : nil
    }
}
