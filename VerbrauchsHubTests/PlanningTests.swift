import XCTest
import UIKit
@testable import VerbrauchsHub

final class PlanningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Monthly readings with a heating-like pattern: heavy in winter, light in summer.
    private func seasonalMeter(until end: Date) -> Meter {
        let monthly: [Decimal] = [300, 250, 200, 120, 60, 30, 30, 30, 60, 120, 200, 280]
        let meter = Meter(type: .gas)
        var value: Decimal = 0
        var cursor = date(2024, 1, 1)
        var readings = [Reading(meter: meter, date: cursor, value: 0)]
        while cursor < end {
            let month = calendar.component(.month, from: cursor)
            value += monthly[month - 1]
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
            readings.append(Reading(meter: meter, date: cursor, value: value))
        }
        meter.readings = readings
        return meter
    }

    // MARK: - Projection

    func testProjectionFollowsLastYearsSeason() throws {
        let meter = seasonalMeter(until: date(2025, 7, 1))
        let calc = ConsumptionCalculator(meter: meter)
        let projection = try XCTUnwrap(calc.projection(from: date(2025, 1, 1), to: date(2026, 1, 1), asOf: date(2025, 7, 1), calendar: calendar))
        XCTAssertTrue(projection.usesPreviousYear)
        XCTAssertEqual(projection.actual.doubleValue, 960, accuracy: 1)
        // Same pattern as 2024 → same annual total, not 2 × the heating-heavy first half.
        XCTAssertEqual(projection.total.doubleValue, 1680, accuracy: 2)
    }

    func testProjectionWithoutHistoryIsLinear() throws {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 7, 1), value: 181),
        ]
        let projection = try XCTUnwrap(ConsumptionCalculator(meter: meter).projection(from: date(2025, 1, 1), to: date(2026, 1, 1), asOf: date(2025, 10, 1), calendar: calendar))
        XCTAssertFalse(projection.usesPreviousYear)
        XCTAssertEqual(projection.total.doubleValue, 365, accuracy: 1)
    }

    func testNoProjectionFromAFewDays() {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 1, 5), value: 20),
        ]
        XCTAssertNil(ConsumptionCalculator(meter: meter).projection(from: date(2025, 1, 1), to: date(2026, 1, 1), asOf: date(2025, 1, 6), calendar: calendar))
    }

    // MARK: - Meter change

    func testConsumptionContinuesAcrossMeterChange() {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 1000),
            Reading(meter: meter, date: date(2025, 1, 11), value: 0, previousMeterFinalValue: 1100), // 100 on the old meter
            Reading(meter: meter, date: date(2025, 1, 21), value: 50),                               // 50 on the new meter
        ]
        let calc = ConsumptionCalculator(meter: meter)
        XCTAssertEqual(calc.totalConsumption(from: date(2025, 1, 1), to: date(2025, 1, 21), calendar: calendar).amount.doubleValue, 150, accuracy: 0.01)
        // Boundary exactly on the change day.
        XCTAssertEqual(calc.totalConsumption(from: date(2025, 1, 1), to: date(2025, 1, 11), calendar: calendar).amount.doubleValue, 100, accuracy: 0.01)
        XCTAssertEqual(calc.totalConsumption(from: date(2025, 1, 11), to: date(2025, 1, 21), calendar: calendar).amount.doubleValue, 50, accuracy: 0.01)
    }

    func testMeterChangeAsFirstReadingIsIgnored() {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0, previousMeterFinalValue: 500),
            Reading(meter: meter, date: date(2025, 1, 11), value: 10),
        ]
        XCTAssertEqual(ConsumptionCalculator(meter: meter).totalConsumption(from: date(2025, 1, 1), to: date(2025, 1, 11), calendar: calendar).amount.doubleValue, 10, accuracy: 0.01)
    }

    func testMeterChangeIsNotFlaggedButLowFinalValueIs() {
        let readings = [Reading(date: date(2025, 1, 1), value: 1000)]
        XCTAssertNil(ReadingCheck.evaluate(value: 0, date: date(2025, 1, 11), readings: readings, previousMeterFinalValue: 1100))
        XCTAssertEqual(ReadingCheck.evaluate(value: 0, date: date(2025, 1, 11), readings: readings, previousMeterFinalValue: 900), .lowerThanPrevious(previous: 1000))
    }

    func testUsualRateIgnoresMeterChangeInHistory() {
        // 10/day before and after a change. Raw value differences would make the history negative
        // and silently skip the check; 70/day must still be flagged.
        let readings = [
            Reading(date: date(2025, 1, 1), value: 1000),
            Reading(date: date(2025, 1, 31), value: 0, previousMeterFinalValue: 1300),
            Reading(date: date(2025, 3, 2), value: 300),
        ]
        XCTAssertNil(ReadingCheck.evaluate(value: 400, date: date(2025, 3, 12), readings: readings))
        XCTAssertEqual(ReadingCheck.evaluate(value: 1000, date: date(2025, 3, 12), readings: readings), .unusuallyHigh(factor: 7))
    }

    // MARK: - Billing

    func testBillingPeriodRepeatsYearly() {
        let anchor = date(2023, 4, 15)
        let period = BillingForecaster.period(anchor: anchor, containing: date(2025, 2, 1), calendar: calendar)
        XCTAssertEqual(period.start, date(2024, 4, 15))
        XCTAssertEqual(period.end, date(2025, 4, 15))
        XCTAssertEqual(BillingForecaster.period(anchor: anchor, containing: date(2025, 4, 15), calendar: calendar).start, date(2025, 4, 15))
        // Anchor in the future (start of next contract year) still yields the running period.
        XCTAssertEqual(BillingForecaster.period(anchor: date(2026, 1, 1), containing: date(2025, 6, 1), calendar: calendar).start, date(2025, 1, 1))
    }

    func testBillingForecastAndSuggestedAdvance() throws {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 7, 1), value: 181),
        ]
        meter.tariffs = [Tariff(meter: meter, pricePerUnit: Decimal(string: "0.30")!, baseFeePerMonth: 10, validFrom: date(2024, 1, 1))]
        meter.advancePayments = [AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))]
        meter.billingStartDate = date(2025, 1, 1)

        let forecast = try XCTUnwrap(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
        XCTAssertEqual(forecast.projectedConsumption.doubleValue, 365, accuracy: 1)
        XCTAssertEqual(forecast.projectedCost.doubleValue, 365 * 0.30 + 120, accuracy: 1.5)
        XCTAssertEqual(forecast.advancePayments, 600)
        XCTAssertLessThan(forecast.balance, 0)
        XCTAssertEqual(forecast.suggestedAdvance, 20)
    }

    func testBillingForecastUsesPlannedTariff() throws {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 7, 1), value: 181),
        ]
        // Current contract ends on 1 Oct, the next one is already known.
        meter.tariffs = [
            Tariff(meter: meter, pricePerUnit: Decimal(string: "0.30")!, baseFeePerMonth: 10, validFrom: date(2024, 1, 1), validTo: date(2025, 10, 1)),
            Tariff(meter: meter, pricePerUnit: Decimal(string: "0.40")!, baseFeePerMonth: 12, validFrom: date(2025, 10, 1)),
        ]
        meter.advancePayments = [AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))]
        meter.billingStartDate = date(2025, 1, 1)

        let forecast = try XCTUnwrap(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
        // 1 unit per day: 273 days (Jan–Sep) at the old price, 92 days (Oct–Dec) at the new one.
        let month = 30.4375
        let expected = 273 * 0.30 + 92 * 0.40 + 273 / month * 10 + 92 / month * 12
        XCTAssertEqual(forecast.projectedCost.doubleValue, expected, accuracy: 1.5)
    }

    func testTariffStatus() {
        let tariff = Tariff(pricePerUnit: 1, validFrom: date(2027, 1, 1), validTo: date(2028, 1, 1))
        XCTAssertEqual(tariff.status(on: date(2026, 11, 26)), .planned)
        XCTAssertEqual(tariff.status(on: date(2027, 1, 1)), .current)
        XCTAssertEqual(tariff.status(on: date(2028, 1, 1)), .ended)
        XCTAssertEqual(Tariff(pricePerUnit: 1, validFrom: date(2024, 1, 1)).status(on: date(2026, 11, 26)), .current)
    }

    func testTariffChainHasNoOverlapForOlderTariffAddedLater() {
        let current = Tariff(pricePerUnit: 1, validFrom: date(2025, 1, 1))
        let older = Tariff(pricePerUnit: 2, validFrom: date(2024, 1, 1))
        let planned = Tariff(pricePerUnit: 3, validFrom: date(2027, 1, 1))
        ValidityChain.relink([current, planned, older])
        XCTAssertEqual(older.validTo, date(2025, 1, 1))
        XCTAssertEqual(current.validTo, date(2027, 1, 1))
        XCTAssertNil(planned.validTo)
    }

    func testDeletingLastTariffReopensPrevious() {
        let old = Tariff(pricePerUnit: 1, validFrom: date(2024, 1, 1), validTo: date(2027, 1, 1))
        // The planned tariff was deleted: only the old one is left.
        ValidityChain.relink([old])
        XCTAssertNil(old.validTo)
    }

    func testCostIsNotCountedTwiceAfterRelink() {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 1, 11), value: 10),
        ]
        let a = Tariff(meter: meter, pricePerUnit: 1, validFrom: date(2024, 1, 1))
        let b = Tariff(meter: meter, pricePerUnit: 1, validFrom: date(2025, 1, 6))
        meter.tariffs = [a, b]
        ValidityChain.relink(meter.tariffs)
        let cost = CostCalculator(meter: meter).cost(in: Period(granularity: .day, start: date(2025, 1, 1), end: date(2025, 1, 11)), calendar: calendar)
        XCTAssertEqual(cost.energyCost.doubleValue, 10, accuracy: 0.01)
    }

    func testAdvancePaymentsChain() {
        let a = AdvancePayment(amountPerMonth: 90, validFrom: date(2025, 1, 1))
        let b = AdvancePayment(amountPerMonth: 105, validFrom: date(2027, 1, 1))
        ValidityChain.relink([b, a])
        XCTAssertEqual(a.validTo, date(2027, 1, 1))
        XCTAssertNil(b.validTo)
        XCTAssertEqual(b.status(on: date(2026, 11, 26)), .planned)
        XCTAssertEqual(a.status(on: date(2026, 11, 26)), .current)
    }

    /// 1 unit per day through the first half of 2025, tariff 0.30 €/unit + 10 €/month, billing from 1 Jan.
    private func linearMeter() -> Meter {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 7, 1), value: 181),
        ]
        meter.tariffs = [Tariff(meter: meter, pricePerUnit: Decimal(string: "0.30")!, baseFeePerMonth: 10, validFrom: date(2024, 1, 1))]
        meter.billingStartDate = date(2025, 1, 1)
        return meter
    }

    func testAdvanceChangeMidYear() throws {
        let meter = linearMeter()
        let a = AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))
        let b = AdvancePayment(meter: meter, amountPerMonth: 80, validFrom: date(2025, 10, 1))
        meter.advancePayments = [a, b]
        ValidityChain.relink(meter.advancePayments)
        let forecast = try XCTUnwrap(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
        // Nine payments of 50 (Jan–Sep), three of 80 (Oct–Dec).
        XCTAssertEqual(forecast.advancePayments, 9 * 50 + 3 * 80)
    }

    func testAdvanceStartingMidYearCountsOnlyFromStart() throws {
        let meter = linearMeter()
        meter.advancePayments = [AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2025, 7, 1))]
        let forecast = try XCTUnwrap(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
        XCTAssertEqual(forecast.advancePayments, 6 * 50) // Jul–Dec
    }

    func testNoBillingWithoutAdvanceInPeriod() {
        let meter = linearMeter()
        XCTAssertNil(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
        // An advance that already ended before the billing year does not count either.
        meter.advancePayments = [AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2023, 1, 1), validTo: date(2024, 6, 1))]
        XCTAssertNil(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
    }

    func testCurrentAndPlannedAdvance() {
        let meter = linearMeter()
        let a = AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))
        let b = AdvancePayment(meter: meter, amountPerMonth: 80, validFrom: date(2027, 1, 1))
        meter.advancePayments = [a, b]
        ValidityChain.relink(meter.advancePayments)
        XCTAssertEqual(meter.advance(on: date(2026, 11, 26))?.amountPerMonth, 50)
        XCTAssertEqual(meter.nextPlannedAdvance(after: date(2026, 11, 26))?.amountPerMonth, 80)
        XCTAssertNil(meter.nextPlannedAdvance(after: date(2027, 2, 1)))
    }

    func testNoBillingWithoutTariffOrForFeedIn() {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 7, 1), value: 181),
        ]
        meter.advancePayments = [AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))]
        meter.billingStartDate = date(2025, 1, 1)
        XCTAssertNil(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))

        let feedIn = Meter(type: .electricityFeedIn)
        feedIn.advancePayments = [AdvancePayment(meter: feedIn, amountPerMonth: 50, validFrom: date(2024, 1, 1))]
        feedIn.billingStartDate = date(2025, 1, 1)
        XCTAssertNil(BillingForecaster.forecast(for: feedIn, asOf: date(2025, 7, 15), calendar: calendar))
    }

    // MARK: - Plausibility

    private func steadyMeter() -> Meter {
        let meter = Meter(type: .water)
        meter.readings = (0..<4).map { Reading(meter: meter, date: date(2025, 1, 1).addingTimeInterval(Double($0) * 30 * 86_400), value: Decimal($0 * 30)) }
        return meter
    }

    func testNormalReadingPasses() {
        let meter = steadyMeter()
        XCTAssertNil(ReadingCheck.evaluate(value: 125, date: date(2025, 5, 1), readings: meter.readings))
    }

    func testLowerValueIsFlagged() {
        let meter = steadyMeter()
        XCTAssertEqual(ReadingCheck.evaluate(value: 80, date: date(2025, 5, 1), readings: meter.readings), .lowerThanPrevious(previous: 90))
    }

    func testTypoWithExtraDigitIsFlagged() {
        let meter = steadyMeter()
        guard case .unusuallyHigh(let factor) = ReadingCheck.evaluate(value: 1200, date: date(2025, 5, 1), readings: meter.readings) else {
            return XCTFail("expected warning")
        }
        XCTAssertGreaterThan(factor, 10)
    }

    func testEditingIgnoresTheReadingItself() {
        let meter = steadyMeter()
        let last = meter.readings.max { $0.date < $1.date }!
        XCTAssertNil(ReadingCheck.evaluate(value: 88, date: last.date, readings: meter.readings, editing: last))
    }

    // MARK: - Recognition

    func testDecimalPlacesFromRedDrumAreInferred() {
        let values = MeterValueRecognizer.candidates(from: ["216128", "kWh", "50 Hz"], previous: 21600)
        XCTAssertEqual(values.first, Decimal(string: "21612.8"))
    }

    func testSplitDrumDigitsAreJoined() {
        let values = MeterValueRecognizer.candidates(from: ["Nr. 12", "0 2 1 6 1 2"], previous: nil)
        XCTAssertEqual(values.first, 21612)
    }

    func testCommaValueIsReadDirectly() {
        let values = MeterValueRecognizer.candidates(from: ["Zählerstand 1234,56 m³"], previous: 1200)
        XCTAssertEqual(values.first, Decimal(string: "1234.56"))
    }

    func testImplausibleNumbersRankBehind() {
        let values = MeterValueRecognizer.candidates(from: ["2019", "04712"], previous: 4700)
        XCTAssertEqual(values.first, 4712)
    }

    func testRecognizesRenderedCounter() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 120, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("021612" as NSString).draw(at: CGPoint(x: 80, y: 60), withAttributes: attributes)
            ("kWh" as NSString).draw(at: CGPoint(x: 700, y: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 40)])
        }
        let data = try XCTUnwrap(image.pngData())
        let values = await MeterValueRecognizer.recognize(imageData: data, previous: 21_500)
        XCTAssertEqual(values.first, 21_612)
    }
}
