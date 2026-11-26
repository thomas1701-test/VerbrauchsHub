import Foundation
import SwiftData

@Model
final class Tariff: ValidityPeriod {
    @Attribute(.unique) var id: UUID
    var meter: Meter?
    var pricePerUnit: Decimal
    var baseFeePerMonth: Decimal
    var feedInPricePerUnit: Decimal?
    var validFrom: Date
    var validTo: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        meter: Meter? = nil,
        pricePerUnit: Decimal,
        baseFeePerMonth: Decimal = 0,
        feedInPricePerUnit: Decimal? = nil,
        validFrom: Date,
        validTo: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.meter = meter
        self.pricePerUnit = pricePerUnit
        self.baseFeePerMonth = baseFeePerMonth
        self.feedInPricePerUnit = feedInPricePerUnit
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdAt = createdAt
    }
}
