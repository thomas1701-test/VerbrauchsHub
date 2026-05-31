import Testing
import Foundation
@testable import VerbrauchsHub

@Suite struct ConsumptionCalculatorTests {

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func emptyReadings() {
        let calc = ConsumptionCalculator(readings: [])
        let period = Period(granularity: .month, start: date(2025, 1, 1), end: date(2025, 2, 1))
        #expect(calc.consumption(in: period, calendar: calendar).hasCoverage == false)
    }

    @Test func consumptionWithinPair() {
        // 100 kWh growth over 100 days → 1/day. 30 days inside the period.
        let r1 = makeReading(date: date(2025, 1, 1), value: 0)
        let r2 = makeReading(date: date(2025, 4, 11), value: 100)
        let calc = ConsumptionCalculator(readings: [r1, r2])
        let period = Period(granularity: .month, start: date(2025, 2, 1), end: date(2025, 3, 1))
        let result = calc.consumption(in: period, calendar: calendar)
        let expected: Decimal = (Decimal(100) * Decimal(28)) / Decimal(100)
        let actual = result.amount
        let diff = actual - expected
        #expect(abs(diff.doubleValue) < 0.5)
    }

    @Test func partialFlagWhenPeriodExtendsBeyondData() {
        let r1 = makeReading(date: date(2025, 1, 1), value: 0)
        let r2 = makeReading(date: date(2025, 1, 15), value: 14)
        let calc = ConsumptionCalculator(readings: [r1, r2])
        // period beyond data
        let period = Period(granularity: .month, start: date(2025, 1, 1), end: date(2025, 2, 1))
        let result = calc.consumption(in: period, calendar: calendar)
        #expect(result.isPartial == true)
        // 14 units over full window only counted for the covered 14 days
        #expect(result.amount.doubleValue == 14)
    }

    @Test func noCoverageReturnsEmpty() {
        let r1 = makeReading(date: date(2025, 1, 1), value: 0)
        let r2 = makeReading(date: date(2025, 1, 15), value: 14)
        let calc = ConsumptionCalculator(readings: [r1, r2])
        let period = Period(granularity: .month, start: date(2025, 6, 1), end: date(2025, 7, 1))
        let result = calc.consumption(in: period, calendar: calendar)
        #expect(result.hasCoverage == false)
    }

    @Test func multipleReadingPairsAggregated() {
        let r1 = makeReading(date: date(2025, 1, 1), value: 0)
        let r2 = makeReading(date: date(2025, 2, 1), value: 31)   // 1/day in January
        let r3 = makeReading(date: date(2025, 3, 1), value: 31 + 56) // 2/day in February (28 days)
        let calc = ConsumptionCalculator(readings: [r1, r2, r3])
        let period = Period(granularity: .month, start: date(2025, 1, 15), end: date(2025, 2, 15))
        let result = calc.consumption(in: period, calendar: calendar)
        // 17 days Jan @1/day + 14 days Feb @2/day = 17+28 = 45
        let actual = result.amount.doubleValue
        #expect(abs(actual - 45.0) < 0.5)
    }

    private func makeReading(date: Date, value: Decimal) -> Reading {
        Reading(date: date, value: value)
    }
}

@Suite struct PeriodGranularityTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test func monthBoundaries() {
        let mid = calendar.date(from: DateComponents(year: 2025, month: 7, day: 17, hour: 12))!
        let start = PeriodGranularity.month.startDate(containing: mid, calendar: calendar)
        let end = PeriodGranularity.month.endDate(after: start, calendar: calendar)
        #expect(calendar.component(.day, from: start) == 1)
        #expect(calendar.component(.month, from: start) == 7)
        #expect(calendar.component(.month, from: end) == 8)
    }

    @Test func quarterBoundaries() {
        let mid = calendar.date(from: DateComponents(year: 2025, month: 8, day: 15, hour: 12))!
        let start = PeriodGranularity.quarter.startDate(containing: mid, calendar: calendar)
        #expect(calendar.component(.month, from: start) == 7)
    }

    @Test func yearPeriods() {
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let periods = PeriodGranularity.year.periods(from: start, to: end, calendar: calendar)
        #expect(periods.count == 3)
    }
}

@Suite struct CostCalculatorTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func tariffPriceApplied() {
        // Build an in-memory meter + readings + tariff manually
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 2, 1), value: 100)
        ]
        meter.tariffs = [
            Tariff(meter: meter, pricePerUnit: Decimal(0.50), baseFeePerMonth: 0, validFrom: date(2025, 1, 1))
        ]
        let calc = CostCalculator(meter: meter)
        let period = Period(granularity: .month, start: date(2025, 1, 1), end: date(2025, 2, 1))
        let result = calc.cost(in: period, calendar: calendar)
        // 100 kWh * 0.50 €/kWh = 50€ exact
        #expect(abs(result.energyCost.doubleValue - 50.0) < 0.01)
    }
}
