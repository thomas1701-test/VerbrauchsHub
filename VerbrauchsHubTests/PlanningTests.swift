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
        meter.advancePaymentPerMonth = 50
        meter.billingStartDate = date(2025, 1, 1)

        let forecast = try XCTUnwrap(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
        XCTAssertEqual(forecast.projectedConsumption.doubleValue, 365, accuracy: 1)
        XCTAssertEqual(forecast.projectedCost.doubleValue, 365 * 0.30 + 120, accuracy: 1.5)
        XCTAssertEqual(forecast.advancePayments, 600)
        XCTAssertLessThan(forecast.balance, 0)
        XCTAssertEqual(forecast.suggestedAdvance, 20)
    }

    func testNoBillingWithoutTariffOrForFeedIn() {
        let meter = Meter(type: .electricity)
        meter.readings = [
            Reading(meter: meter, date: date(2025, 1, 1), value: 0),
            Reading(meter: meter, date: date(2025, 7, 1), value: 181),
        ]
        meter.advancePaymentPerMonth = 50
        meter.billingStartDate = date(2025, 1, 1)
        XCTAssertNil(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))

        let feedIn = Meter(type: .electricityFeedIn)
        feedIn.advancePaymentPerMonth = 50
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
