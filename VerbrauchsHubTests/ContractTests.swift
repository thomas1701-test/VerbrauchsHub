import XCTest
@testable import VerbrauchsHub

final class ContractTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private let today = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 26))!

    private func contract(termEnd: Date?, notice: (Int, NoticeUnit)?, renewal: Int?) -> Contract {
        let c = Contract(provider: "Test", startDate: date(2024, 1, 1))
        c.minimumTermEnd = termEnd
        c.noticePeriodValue = notice?.0
        c.noticeUnit = notice?.1
        c.renewalMonths = renewal
        return c
    }

    // MARK: - Cancellation

    func testDeadlineBeforeMinimumTermEnd() {
        let c = contract(termEnd: date(2027, 1, 31), notice: (1, .months), renewal: nil)
        XCTAssertEqual(c.cancellation(asOf: today, calendar: calendar), .deadline(date: date(2026, 12, 31), termEnd: date(2027, 1, 31)))
    }

    func testDeadlineAtEndOfFebruary() {
        let c = contract(termEnd: date(2027, 3, 31), notice: (1, .months), renewal: nil)
        XCTAssertEqual(c.cancellation(asOf: today, calendar: calendar), .deadline(date: date(2027, 2, 28), termEnd: date(2027, 3, 31)))
    }

    func testRenewalRollsForward() {
        let c = contract(termEnd: date(2025, 12, 31), notice: (6, .weeks), renewal: 12)
        XCTAssertEqual(c.cancellation(asOf: today, calendar: calendar), .deadline(date: date(2027, 11, 19), termEnd: date(2027, 12, 31)))
    }

    func testRunsOnIndefinitely() {
        let c = contract(termEnd: date(2025, 12, 31), notice: (1, .months), renewal: nil)
        XCTAssertEqual(c.cancellation(asOf: today, calendar: calendar), .anytime(value: 1, unit: .months))
    }

    func testMissingDataGivesNoCancellation() {
        XCTAssertNil(contract(termEnd: nil, notice: (1, .months), renewal: nil).cancellation(asOf: today, calendar: calendar))
        XCTAssertNil(contract(termEnd: date(2027, 1, 31), notice: nil, renewal: nil).cancellation(asOf: today, calendar: calendar))
    }

    func testDeadlineOnTodayIsStillOpen() {
        let c = contract(termEnd: date(2026, 12, 26), notice: (1, .months), renewal: nil)
        XCTAssertEqual(c.cancellation(asOf: today, calendar: calendar), .deadline(date: today, termEnd: date(2026, 12, 26)))
    }

    // MARK: - Status

    func testContractStatusFromTariffs() {
        let planned = Contract(provider: "Neu", startDate: date(2027, 1, 1))
        planned.tariffs = [Tariff(pricePerUnit: 1, validFrom: date(2027, 1, 1))]
        XCTAssertEqual(planned.status(on: today), .planned)

        let running = Contract(provider: "Alt", startDate: date(2024, 1, 1))
        running.tariffs = [
            Tariff(pricePerUnit: 1, validFrom: date(2024, 1, 1), validTo: date(2025, 1, 1)),
            Tariff(pricePerUnit: 2, validFrom: date(2025, 1, 1), validTo: date(2027, 1, 1)),
        ]
        XCTAssertEqual(running.status(on: today), .current)
        XCTAssertEqual(running.status(on: date(2027, 2, 1)), .ended)

        XCTAssertNil(Contract(provider: "Leer", startDate: date(2024, 1, 1)).status(on: today))
    }

    // MARK: - Reminders

    private func at9(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    func testRemindersForDeadlineAndPriceGuarantee() {
        let c = contract(termEnd: date(2027, 1, 31), notice: (1, .months), renewal: nil)
        c.priceGuaranteeUntil = date(2027, 3, 31)
        XCTAssertEqual(c.reminders(asOf: today, calendar: calendar), [
            ContractReminder(kind: .cancellation, fireDate: at9(2026, 12, 1), eventDate: date(2026, 12, 31)),
            ContractReminder(kind: .priceGuarantee, fireDate: at9(2027, 3, 1), eventDate: date(2027, 3, 31)),
        ])
    }

    func testRemindersInThePastAreSkipped() {
        // Deadline 31 Dec, but only 10 days before is too late for a 30-day lead.
        let c = contract(termEnd: date(2027, 1, 31), notice: (1, .months), renewal: nil)
        XCTAssertEqual(c.reminders(asOf: date(2026, 12, 21), calendar: calendar), [])
    }

    func testNoRemindersWhenDisabledOrAnytime() {
        let disabled = contract(termEnd: date(2027, 1, 31), notice: (1, .months), renewal: nil)
        disabled.reminderEnabled = false
        disabled.priceGuaranteeUntil = date(2027, 3, 31)
        XCTAssertEqual(disabled.reminders(asOf: today, calendar: calendar), [])
        let anytime = contract(termEnd: date(2025, 12, 31), notice: (1, .months), renewal: nil)
        XCTAssertEqual(anytime.reminders(asOf: today, calendar: calendar), [])
    }

    // MARK: - Review fixes

    func testDeadlineDayStaysOpenAllDay() {
        // Term end stored with the picker's time of day; on the deadline day itself it is still open.
        let c = contract(termEnd: date(2026, 12, 26).addingTimeInterval(9 * 3600), notice: (1, .months), renewal: 12)
        let evening = today.addingTimeInterval(20 * 3600)
        guard case .deadline(let deadline, _) = c.cancellation(asOf: evening, calendar: calendar) else {
            return XCTFail("expected a deadline")
        }
        XCTAssertEqual(calendar.startOfDay(for: deadline), today)
    }

    func testEndedContractSendsNoReminders() {
        let c = contract(termEnd: date(2025, 12, 31), notice: (1, .months), renewal: 12)
        c.priceGuaranteeUntil = date(2027, 3, 31)
        c.tariffs = [Tariff(pricePerUnit: 1, validFrom: date(2024, 1, 1), validTo: date(2026, 1, 1))]
        XCTAssertEqual(c.reminders(asOf: today, calendar: calendar), [])
    }

    func testContractReminderIdentifiersAreFound() {
        let ids = ["meter-reminder-1", "contract-cancel-A", "contract-guarantee-B", "other"]
        XCTAssertEqual(NotificationService.contractReminderIDs(in: ids), ["contract-cancel-A", "contract-guarantee-B"])
    }
}
