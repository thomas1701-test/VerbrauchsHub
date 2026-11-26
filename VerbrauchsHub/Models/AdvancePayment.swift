import Foundation
import SwiftData

/// Monthly advance payment (Abschlag) to the supplier, valid from a date on.
@Model
final class AdvancePayment: ValidityPeriod {
    @Attribute(.unique) var id: UUID
    var meter: Meter?
    var amountPerMonth: Decimal
    var validFrom: Date
    var validTo: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        meter: Meter? = nil,
        amountPerMonth: Decimal,
        validFrom: Date,
        validTo: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.meter = meter
        self.amountPerMonth = amountPerMonth
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdAt = createdAt
    }
}

extension Meter {
    /// The advance payment due on `date`.
    func advance(on date: Date) -> AdvancePayment? {
        advancePayments.first { $0.isActive(on: date) }
    }

    /// Without a billing start the forecast cannot run; the calendar year of the first advance
    /// is the most common billing year.
    func ensureBillingStart(for payment: AdvancePayment, calendar: Calendar = .current) {
        guard billingStartDate == nil else { return }
        billingStartDate = calendar.dateInterval(of: .year, for: payment.validFrom)?.start
    }

    /// The next advance payment that starts after `date`, if one is already stored.
    func nextPlannedAdvance(after date: Date) -> AdvancePayment? {
        advancePayments.filter { $0.validFrom > date }.min { $0.validFrom < $1.validFrom }
    }
}
