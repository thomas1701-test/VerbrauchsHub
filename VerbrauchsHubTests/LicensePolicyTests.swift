import XCTest
@testable import VerbrauchsHub

final class LicensePolicyTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let afterSwitch = LicensePolicy.freeSwitchCutoff.addingTimeInterval(24 * 60 * 60)
    private let beforeSwitch = LicensePolicy.freeSwitchCutoff.addingTimeInterval(-24 * 60 * 60)

    // MARK: - Existing customers

    func testEveryPaidBuildIsLegacy() {
        for build in ["1", "2", "3"] {
            XCTAssertTrue(LicensePolicy.isLegacy(originalBuild: build, originalPurchaseDate: afterSwitch, isProduction: true), build)
        }
    }

    func testFirstFreeBuildAfterCutoffIsNotLegacy() {
        XCTAssertFalse(LicensePolicy.isLegacy(originalBuild: "4", originalPurchaseDate: afterSwitch, isProduction: true))
        XCTAssertFalse(LicensePolicy.isLegacy(originalBuild: "12", originalPurchaseDate: afterSwitch, isProduction: true))
    }

    /// Bought during the switch-over, while the new build was out but the price not yet free.
    func testNewBuildBeforeCutoffIsLegacy() {
        XCTAssertTrue(LicensePolicy.isLegacy(originalBuild: "4", originalPurchaseDate: beforeSwitch, isProduction: true))
    }

    func testUnparsableBuildFallsBackToDate() {
        XCTAssertTrue(LicensePolicy.isLegacy(originalBuild: "1.0", originalPurchaseDate: beforeSwitch, isProduction: true))
        XCTAssertFalse(LicensePolicy.isLegacy(originalBuild: "1.0", originalPurchaseDate: afterSwitch, isProduction: true))
    }

    /// TestFlight and Xcode report "1.0" and the install date – they must be able to test the trial.
    func testSandboxIsNeverLegacy() {
        XCTAssertFalse(LicensePolicy.isLegacy(originalBuild: "1", originalPurchaseDate: beforeSwitch, isProduction: false))
    }

    // MARK: - State

    func testPurchaseWinsOverEverything() {
        for verdict in [LegacyVerdict.legacy, .notLegacy, .unknown] {
            XCTAssertEqual(LicensePolicy.state(legacy: verdict, purchased: true, trialStart: .now.addingTimeInterval(-30 * day), now: .now), .purchased)
        }
    }

    func testLegacyIgnoresExpiredTrial() {
        XCTAssertEqual(LicensePolicy.state(legacy: .legacy, purchased: false, trialStart: .now.addingTimeInterval(-30 * day), now: .now), .legacy)
    }

    func testUnknownNeverLocks() {
        let state = LicensePolicy.state(legacy: .unknown, purchased: false, trialStart: .now.addingTimeInterval(-30 * day), now: .now)
        XCTAssertEqual(state, .unknown)
        XCTAssertTrue(state.isUsable)
        XCTAssertTrue(LicensePolicy.state(legacy: .unknown, purchased: false, trialStart: nil, now: .now).isUsable)
    }

    func testNewUserMustStartTrial() {
        XCTAssertEqual(LicensePolicy.state(legacy: .notLegacy, purchased: false, trialStart: nil, now: .now), .trialNotStarted)
    }

    func testTrialRunsFourteenDays() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(14 * day)
        XCTAssertEqual(LicensePolicy.state(legacy: .notLegacy, purchased: false, trialStart: start, now: end.addingTimeInterval(-1)), .trial(endsAt: end))
        XCTAssertEqual(LicensePolicy.state(legacy: .notLegacy, purchased: false, trialStart: start, now: end), .expired)
        XCTAssertFalse(LicenseState.expired.isUsable)
    }

    func testDaysLeftRoundsUp() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(LicensePolicy.daysLeft(until: now.addingTimeInterval(14 * day), now: now), 14)
        XCTAssertEqual(LicensePolicy.daysLeft(until: now.addingTimeInterval(13 * day + 60), now: now), 14)
        XCTAssertEqual(LicensePolicy.daysLeft(until: now.addingTimeInterval(60), now: now), 1)
        XCTAssertEqual(LicensePolicy.daysLeft(until: now.addingTimeInterval(-60), now: now), 0)
    }

    // MARK: - Reminders

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Trial started at 10:00; reminders are checked at noon on day `n`.
    private func noon(_ n: Int, from start: Date) -> Date {
        calendar.startOfDay(for: start).addingTimeInterval(Double(n) * day + 12 * 60 * 60)
    }

    func testNoReminderOnFirstDay() {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(10 * 60 * 60)
        XCTAssertFalse(LicensePolicy.shouldRemind(trialStart: start, lastReminder: nil, now: noon(0, from: start), calendar: calendar))
        XCTAssertTrue(LicensePolicy.shouldRemind(trialStart: start, lastReminder: nil, now: noon(1, from: start), calendar: calendar))
    }

    func testReminderScheduleOverWholeTrial() {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(10 * 60 * 60)
        var last: Date?
        var shownOn: [Int] = []
        for n in 0...15 {
            let now = noon(n, from: start)
            if LicensePolicy.shouldRemind(trialStart: start, lastReminder: last, now: now, calendar: calendar) {
                shownOn.append(n)
                last = now
            }
        }
        // Every three days, then daily during the last three days; nothing after the end (day 14, 10:00).
        XCTAssertEqual(shownOn, [1, 4, 7, 10, 11, 12, 13])
    }

    func testOneReminderPerDayAtMost() {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(10 * 60 * 60)
        let morning = noon(12, from: start).addingTimeInterval(-3 * 60 * 60)
        XCTAssertFalse(LicensePolicy.shouldRemind(trialStart: start, lastReminder: morning, now: noon(12, from: start), calendar: calendar))
    }
}
