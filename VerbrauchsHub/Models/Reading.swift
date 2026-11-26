import Foundation
import SwiftData

@Model
final class Reading {
    @Attribute(.unique) var id: UUID
    var meter: Meter?
    var date: Date
    var value: Decimal
    var note: String?
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date
    /// Set on a meter exchange: final value of the old meter on `date`.
    /// `value` is then the start value of the new meter.
    var previousMeterFinalValue: Decimal?

    var isMeterChange: Bool { previousMeterFinalValue != nil }

    init(
        id: UUID = UUID(),
        meter: Meter? = nil,
        date: Date,
        value: Decimal,
        note: String? = nil,
        photoData: Data? = nil,
        createdAt: Date = .now,
        previousMeterFinalValue: Decimal? = nil
    ) {
        self.id = id
        self.meter = meter
        self.date = date
        self.value = value
        self.note = note
        self.photoData = photoData
        self.createdAt = createdAt
        self.previousMeterFinalValue = previousMeterFinalValue
    }
}
