import Foundation

/// What the app may do right now.
enum LicenseState: Equatable {
    /// Waiting for the first answer from StoreKit (only briefly at launch).
    case checking
    /// Downloaded while VerbrauchsHub was still a paid app – unlocked for good.
    case legacy
    /// Bought the full version.
    case purchased
    /// Trial running until `endsAt`.
    case trial(endsAt: Date)
    /// New user who has neither started the trial nor bought the app.
    case trialNotStarted
    /// Trial is over and the full version was not bought.
    case expired
    /// StoreKit gave no reliable answer. The app never locks in this case.
    case unknown

    var isUsable: Bool {
        switch self {
        case .legacy, .purchased, .trial, .unknown: true
        case .checking, .trialNotStarted, .expired: false
        }
    }

    var isFullVersion: Bool {
        self == .legacy || self == .purchased
    }
}

/// Whether the device's Apple account got the app before it became free.
enum LegacyVerdict: Equatable {
    case legacy
    case notLegacy
    /// No verified `AppTransaction` – never treated as "not legacy".
    case unknown
}

/// Pure decision rules, kept free of StoreKit so every case can be unit-tested.
enum LicensePolicy {
    static let trialProductID = "net.gmx.dillmann.VerbrauchsHub.trial14"
    static let fullProductID = "net.gmx.dillmann.VerbrauchsHub.full"

    static let trialDays = 14

    /// Highest build that was ever sold as a paid app (1.0.0 (3)).
    /// `AppTransaction.originalAppVersion` is the CFBundleVersion of the first download.
    static let lastPaidBuild = 3

    /// Second safety net for the switch-over: everyone whose first download lies
    /// before this moment counts as an existing customer, whatever build they got.
    /// Set it a few days *after* the price is changed to free.
    static let freeSwitchCutoff: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 15
        components.timeZone = TimeZone(identifier: "Europe/Berlin")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// - Parameters:
    ///   - originalBuild: `AppTransaction.originalAppVersion`
    ///   - originalPurchaseDate: `AppTransaction.originalPurchaseDate`
    ///   - isProduction: Sandbox and Xcode report placeholder values ("1.0", install date),
    ///     so the legacy rule only applies to App Store downloads.
    static func isLegacy(originalBuild: String, originalPurchaseDate: Date, isProduction: Bool) -> Bool {
        guard isProduction else { return false }
        if let build = Int(originalBuild.trimmingCharacters(in: .whitespaces)), build <= lastPaidBuild {
            return true
        }
        return originalPurchaseDate < freeSwitchCutoff
    }

    static func trialEnd(startedAt start: Date) -> Date {
        start.addingTimeInterval(TimeInterval(trialDays) * 24 * 60 * 60)
    }

    static func state(legacy: LegacyVerdict, purchased: Bool, trialStart: Date?, now: Date) -> LicenseState {
        if purchased { return .purchased }
        switch legacy {
        case .legacy:
            return .legacy
        case .unknown:
            // Without a verified answer nobody gets locked out.
            return .unknown
        case .notLegacy:
            guard let trialStart else { return .trialNotStarted }
            let end = trialEnd(startedAt: trialStart)
            return now < end ? .trial(endsAt: end) : .expired
        }
    }

    /// Whole days left in the trial, counted up (13 days and 2 hours → 14).
    static func daysLeft(until end: Date, now: Date) -> Int {
        max(0, Int((end.timeIntervalSince(now) / (24 * 60 * 60)).rounded(.up)))
    }

    /// Reminder to buy during the trial: not on the first day, then every three
    /// days, and daily during the last three days.
    static func shouldRemind(trialStart: Date, lastReminder: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        let end = trialEnd(startedAt: trialStart)
        guard now >= trialStart, now < end else { return false }

        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.startOfDay(for: trialStart)
        guard let sinceStart = calendar.dateComponents([.day], from: firstDay, to: today).day, sinceStart >= 1 else {
            return false
        }
        guard let lastReminder else { return true }

        let interval = daysLeft(until: end, now: now) <= 3 ? 1 : 3
        let lastDay = calendar.startOfDay(for: lastReminder)
        let sinceLast = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return sinceLast >= interval
    }
}
