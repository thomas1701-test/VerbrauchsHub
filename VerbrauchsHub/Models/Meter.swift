import Foundation
import SwiftData

@Model
final class Meter {
    @Attribute(.unique) var id: UUID
    var building: Building?
    var typeRaw: String
    var customName: String?
    var unitRaw: String
    var unitCustomLabel: String?
    var iconName: String
    var colorHex: String
    var reminderEnabled: Bool
    var reminderDayOfMonth: Int?
    var createdAt: Date
    /// Monthly advance payment to the supplier (Abschlag) in euros.
    var advancePaymentPerMonth: Decimal?
    /// Start of a billing period; the period repeats yearly from this date.
    var billingStartDate: Date?
    /// Consumption goal per calendar year in the meter's unit.
    var annualTarget: Decimal?

    @Relationship(deleteRule: .cascade, inverse: \Reading.meter)
    var readings: [Reading] = []

    @Relationship(deleteRule: .cascade, inverse: \Tariff.meter)
    var tariffs: [Tariff] = []

    @Relationship(deleteRule: .cascade, inverse: \AdvancePayment.meter)
    var advancePayments: [AdvancePayment] = []

    @Relationship(deleteRule: .cascade, inverse: \Contract.meter)
    var contracts: [Contract] = []

    init(
        id: UUID = UUID(),
        building: Building? = nil,
        type: MeterType,
        customName: String? = nil,
        unit: Unit? = nil,
        unitCustomLabel: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        reminderEnabled: Bool = false,
        reminderDayOfMonth: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.building = building
        self.typeRaw = type.rawValue
        self.customName = customName
        let resolvedUnit = unit ?? type.defaultUnit
        self.unitRaw = resolvedUnit.rawValue
        self.unitCustomLabel = unitCustomLabel
        self.iconName = iconName ?? type.defaultIconName
        self.colorHex = colorHex ?? type.defaultColorHex
        self.reminderEnabled = reminderEnabled
        self.reminderDayOfMonth = reminderDayOfMonth
        self.createdAt = createdAt
    }

    var type: MeterType {
        get { MeterType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    var unit: Unit {
        get { Unit(rawValue: unitRaw) ?? .custom }
        set { unitRaw = newValue.rawValue }
    }

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        return type.localizedName
    }

    var unitLabel: String {
        unit.localizedLabel(custom: unitCustomLabel)
    }
}
