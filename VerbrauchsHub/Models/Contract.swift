import Foundation
import SwiftData

enum NoticeUnit: String, CaseIterable {
    case weeks
    case months

    func label(_ value: Int) -> String {
        switch self {
        case .weeks: value == 1 ? "Woche" : "Wochen"
        case .months: value == 1 ? "Monat" : "Monate"
        }
    }
}

/// Supply contract of a meter: supplier, term, notice period, price guarantee.
/// Its prices are the tariffs that point to it; a price adjustment is a new tariff in the same contract.
@Model
final class Contract {
    @Attribute(.unique) var id: UUID
    var meter: Meter?
    var provider: String
    var customerNumber: String?
    var contractNumber: String?
    var startDate: Date
    /// End of the minimum term (Erstlaufzeit). nil = unknown or no minimum term.
    var minimumTermEnd: Date?
    /// Automatic renewal after the term in months (old contracts often 12). nil = runs on
    /// indefinitely and can be cancelled with the notice period at any time (common since 2022).
    var renewalMonths: Int?
    var noticePeriodValue: Int?
    var noticePeriodUnitRaw: String?
    var priceGuaranteeUntil: Date?
    var notes: String?
    var reminderEnabled: Bool
    var reminderLeadDays: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Tariff.contract)
    var tariffs: [Tariff] = []

    init(
        id: UUID = UUID(),
        meter: Meter? = nil,
        provider: String,
        startDate: Date,
        reminderEnabled: Bool = true,
        reminderLeadDays: Int = 30,
        createdAt: Date = .now
    ) {
        self.id = id
        self.meter = meter
        self.provider = provider
        self.startDate = startDate
        self.reminderEnabled = reminderEnabled
        self.reminderLeadDays = reminderLeadDays
        self.createdAt = createdAt
    }
}

enum Cancellation: Equatable {
    /// Last day the notice can be given, and the end of the term it cancels.
    case deadline(date: Date, termEnd: Date)
    /// Past the minimum term without renewal: cancellable at any time with the notice period.
    case anytime(value: Int, unit: NoticeUnit)
}

extension Contract {
    var noticeUnit: NoticeUnit? {
        get { noticePeriodUnitRaw.flatMap(NoticeUnit.init(rawValue:)) }
        set { noticePeriodUnitRaw = newValue?.rawValue }
    }

    func cancellation(asOf now: Date, calendar: Calendar = .current) -> Cancellation? {
        guard var termEnd = minimumTermEnd,
              let value = noticePeriodValue, value > 0, let unit = noticeUnit else { return nil }
        let component: Calendar.Component = unit == .weeks ? .weekOfYear : .month
        for _ in 0..<100 {
            guard let deadline = calendar.date(byAdding: component, value: -value, to: termEnd) else { return nil }
            if deadline >= now { return .deadline(date: deadline, termEnd: termEnd) }
            guard let renewal = renewalMonths, renewal > 0 else { return .anytime(value: value, unit: unit) }
            guard let next = calendar.date(byAdding: .month, value: renewal, to: termEnd) else { return nil }
            termEnd = next
        }
        return nil
    }

    /// Derived from its prices: current if one applies on `date`, planned if all start later.
    func status(on date: Date) -> ValidityStatus? {
        guard !tariffs.isEmpty else { return nil }
        if tariffs.contains(where: { $0.isActive(on: date) }) { return .current }
        if tariffs.contains(where: { $0.validFrom > date }) { return .planned }
        return .ended
    }
}
