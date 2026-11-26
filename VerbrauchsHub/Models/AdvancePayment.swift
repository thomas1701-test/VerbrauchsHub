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
