import Foundation

struct ForecastResult: Hashable {
    /// Verbrauch year-to-date
    let yearToDate: Decimal
    /// Hochrechnung auf das volle Jahr
    let projectedTotal: Decimal
    /// Bezugsdatum
    let asOf: Date
}

struct Forecaster {
    let calculator: ConsumptionCalculator

    init(meter: Meter) {
        self.calculator = ConsumptionCalculator(meter: meter)
    }

    func yearForecast(asOf date: Date = .now, calendar: Calendar = .current) -> ForecastResult? {
        guard let yearStart = calendar.dateInterval(of: .year, for: date)?.start,
              let yearEnd = calendar.dateInterval(of: .year, for: date)?.end else {
            return nil
        }
        let ytd = calculator.totalConsumption(from: yearStart, to: date, calendar: calendar).amount
        let totalSecondsInYear = yearEnd.timeIntervalSince(yearStart)
        let elapsedSeconds = max(date.timeIntervalSince(yearStart), 1)
        let factor = Decimal(totalSecondsInYear / elapsedSeconds)
        let projected = ytd * factor
        return ForecastResult(yearToDate: ytd, projectedTotal: projected, asOf: date)
    }
}

struct TrendResult: Hashable {
    let current: Decimal
    let previous: Decimal
    var deltaAbsolute: Decimal { current - previous }
    var deltaPercent: Decimal? {
        guard previous != 0 else { return nil }
        return (current - previous) / previous * 100
    }
    var direction: TrendDirection {
        if previous == 0 && current == 0 { return .flat }
        if current > previous { return .up }
        if current < previous { return .down }
        return .flat
    }
}

enum TrendDirection { case up, down, flat }
