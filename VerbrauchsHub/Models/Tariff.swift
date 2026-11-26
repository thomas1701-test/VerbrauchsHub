import Foundation
import SwiftData

@Model
final class Tariff {
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

    func isActive(on date: Date) -> Bool {
        status(on: date) == .current
    }

    /// Chains the tariffs of one meter without gaps or overlaps: each tariff ends where the next
    /// one starts, the latest one stays open. Call after adding or deleting a tariff, passing
    /// the tariffs that remain.
    static func relink(_ tariffs: [Tariff]) {
        let sorted = tariffs.sorted { $0.validFrom < $1.validFrom }
        for (index, tariff) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].validFrom : nil
            if tariff.validTo != next { tariff.validTo = next }
        }
    }

    func status(on date: Date) -> TariffStatus {
        if date < validFrom { return .planned }
        if let validTo, date >= validTo { return .ended }
        return .current
    }
}

enum TariffStatus {
    /// Starts in the future, e.g. a contract already signed for next year.
    case planned
    case current
    case ended
}
