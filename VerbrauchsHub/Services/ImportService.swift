import Foundation
import SwiftData

enum ImportError: LocalizedError {
    case invalidJSON
    case missingSchema
    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Datei ist kein gültiges JSON-Backup."
        case .missingSchema: return "Backup-Version wird nicht unterstützt."
        }
    }
}

enum ImportService {
    enum Strategy { case merge, replace }

    @MainActor
    static func importSnapshot(data: Data, into context: ModelContext, strategy: Strategy) throws -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: ExportSnapshot
        do {
            snapshot = try decoder.decode(ExportSnapshot.self, from: data)
        } catch {
            throw ImportError.invalidJSON
        }
        guard snapshot.schemaVersion == 1 else { throw ImportError.missingSchema }

        if strategy == .replace {
            try deleteAll(context: context)
        }

        // Index existing
        let existingBuildings = (try? context.fetch(FetchDescriptor<Building>())) ?? []
        let existingMeters = (try? context.fetch(FetchDescriptor<Meter>())) ?? []
        let existingReadings = (try? context.fetch(FetchDescriptor<Reading>())) ?? []
        let existingTariffs = (try? context.fetch(FetchDescriptor<Tariff>())) ?? []
        let existingContracts = (try? context.fetch(FetchDescriptor<Contract>())) ?? []
        let existingAdvances = (try? context.fetch(FetchDescriptor<AdvancePayment>())) ?? []

        var buildingsByID: [UUID: Building] = Dictionary(uniqueKeysWithValues: existingBuildings.map { ($0.id, $0) })
        var metersByID: [UUID: Meter] = Dictionary(uniqueKeysWithValues: existingMeters.map { ($0.id, $0) })
        var readingsByID: [UUID: Reading] = Dictionary(uniqueKeysWithValues: existingReadings.map { ($0.id, $0) })
        var tariffsByID: [UUID: Tariff] = Dictionary(uniqueKeysWithValues: existingTariffs.map { ($0.id, $0) })
        var contractsByID: [UUID: Contract] = Dictionary(uniqueKeysWithValues: existingContracts.map { ($0.id, $0) })
        var advancesByID: [UUID: AdvancePayment] = Dictionary(uniqueKeysWithValues: existingAdvances.map { ($0.id, $0) })
        // A 1.2 backup carries the advance history; then the single 1.1 value is only informational.
        let hasAdvanceHistory = snapshot.advancePayments != nil

        var addedBuildings = 0, addedMeters = 0, addedReadings = 0, addedTariffs = 0, addedContracts = 0, addedAdvances = 0
        var updatedCount = 0

        for dto in snapshot.buildings {
            if let existing = buildingsByID[dto.id] {
                existing.name = dto.name
                existing.address = dto.address
                existing.iconName = dto.iconName
                existing.colorHex = dto.colorHex
                existing.notes = dto.notes
                updatedCount += 1
            } else {
                let b = Building(id: dto.id, name: dto.name, address: dto.address, iconName: dto.iconName, colorHex: dto.colorHex, notes: dto.notes, createdAt: dto.createdAt)
                context.insert(b)
                buildingsByID[dto.id] = b
                addedBuildings += 1
            }
        }

        for dto in snapshot.meters {
            let building = dto.buildingID.flatMap { buildingsByID[$0] }
            if let existing = metersByID[dto.id] {
                existing.typeRaw = dto.typeRaw
                existing.customName = dto.customName
                existing.unitRaw = dto.unitRaw
                existing.unitCustomLabel = dto.unitCustomLabel
                existing.iconName = dto.iconName
                existing.colorHex = dto.colorHex
                existing.reminderEnabled = dto.reminderEnabled
                existing.reminderDayOfMonth = dto.reminderDayOfMonth
                existing.advancePaymentPerMonth = hasAdvanceHistory ? nil : dto.advancePaymentPerMonth
                existing.billingStartDate = dto.billingStartDate
                existing.annualTarget = dto.annualTarget
                existing.building = building
                updatedCount += 1
            } else {
                let m = Meter(
                    id: dto.id,
                    building: building,
                    type: MeterType(rawValue: dto.typeRaw) ?? .custom,
                    customName: dto.customName,
                    unit: Unit(rawValue: dto.unitRaw),
                    unitCustomLabel: dto.unitCustomLabel,
                    iconName: dto.iconName,
                    colorHex: dto.colorHex,
                    reminderEnabled: dto.reminderEnabled,
                    reminderDayOfMonth: dto.reminderDayOfMonth,
                    createdAt: dto.createdAt
                )
                m.advancePaymentPerMonth = hasAdvanceHistory ? nil : dto.advancePaymentPerMonth
                m.billingStartDate = dto.billingStartDate
                m.annualTarget = dto.annualTarget
                context.insert(m)
                metersByID[dto.id] = m
                addedMeters += 1
            }
        }

        for dto in snapshot.contracts ?? [] {
            let meter = dto.meterID.flatMap { metersByID[$0] }
            let contract: Contract
            if let existing = contractsByID[dto.id] {
                contract = existing
                updatedCount += 1
            } else {
                contract = Contract(id: dto.id, provider: dto.provider, startDate: dto.startDate, createdAt: dto.createdAt)
                context.insert(contract)
                contractsByID[dto.id] = contract
                addedContracts += 1
            }
            contract.meter = meter
            contract.provider = dto.provider
            contract.customerNumber = dto.customerNumber
            contract.contractNumber = dto.contractNumber
            contract.startDate = dto.startDate
            contract.minimumTermEnd = dto.minimumTermEnd
            contract.renewalMonths = dto.renewalMonths
            contract.noticePeriodValue = dto.noticePeriodValue
            contract.noticePeriodUnitRaw = dto.noticePeriodUnitRaw
            contract.priceGuaranteeUntil = dto.priceGuaranteeUntil
            contract.notes = dto.notes
            contract.reminderEnabled = dto.reminderEnabled
            contract.reminderLeadDays = dto.reminderLeadDays
        }

        for dto in snapshot.readings {
            let meter = dto.meterID.flatMap { metersByID[$0] }
            if let existing = readingsByID[dto.id] {
                existing.date = dto.date
                existing.value = dto.value
                existing.note = dto.note
                existing.photoData = dto.photoData
                existing.previousMeterFinalValue = dto.previousMeterFinalValue
                existing.meter = meter
                updatedCount += 1
            } else {
                let r = Reading(id: dto.id, meter: meter, date: dto.date, value: dto.value, note: dto.note, photoData: dto.photoData, createdAt: dto.createdAt, previousMeterFinalValue: dto.previousMeterFinalValue)
                context.insert(r)
                readingsByID[dto.id] = r
                addedReadings += 1
            }
        }

        for dto in snapshot.tariffs {
            let meter = dto.meterID.flatMap { metersByID[$0] }
            let contract = dto.contractID.flatMap { contractsByID[$0] }
            if let existing = tariffsByID[dto.id] {
                existing.contract = contract
                existing.pricePerUnit = dto.pricePerUnit
                existing.baseFeePerMonth = dto.baseFeePerMonth
                existing.feedInPricePerUnit = dto.feedInPricePerUnit
                existing.validFrom = dto.validFrom
                existing.validTo = dto.validTo
                existing.meter = meter
                updatedCount += 1
            } else {
                let t = Tariff(id: dto.id, meter: meter, pricePerUnit: dto.pricePerUnit, baseFeePerMonth: dto.baseFeePerMonth, feedInPricePerUnit: dto.feedInPricePerUnit, validFrom: dto.validFrom, validTo: dto.validTo, createdAt: dto.createdAt)
                t.contract = contract
                context.insert(t)
                tariffsByID[dto.id] = t
                addedTariffs += 1
            }
        }

        for dto in snapshot.advancePayments ?? [] {
            let meter = dto.meterID.flatMap { metersByID[$0] }
            if let existing = advancesByID[dto.id] {
                existing.meter = meter
                existing.amountPerMonth = dto.amountPerMonth
                existing.validFrom = dto.validFrom
                existing.validTo = dto.validTo
                updatedCount += 1
            } else {
                let a = AdvancePayment(id: dto.id, meter: meter, amountPerMonth: dto.amountPerMonth, validFrom: dto.validFrom, validTo: dto.validTo, createdAt: dto.createdAt)
                context.insert(a)
                advancesByID[dto.id] = a
                addedAdvances += 1
            }
        }

        try context.save()
        DataMigration.run(context)
        for meter in (try? context.fetch(FetchDescriptor<Meter>())) ?? [] {
            ValidityChain.relink(meter.tariffs)
            ValidityChain.relink(meter.advancePayments)
        }
        try context.save()
        NotificationService.shared.rescheduleAllContractReminders(context)

        return "Import erfolgreich: +\(addedBuildings) Gebäude, +\(addedMeters) Zähler, +\(addedReadings) Ablesungen, +\(addedTariffs) Tarife, +\(addedContracts) Verträge, +\(addedAdvances) Abschläge, \(updatedCount) aktualisiert."
    }

    private static func deleteAll(context: ModelContext) throws {
        try context.delete(model: Reading.self)
        try context.delete(model: Tariff.self)
        try context.delete(model: AdvancePayment.self)
        try context.delete(model: Contract.self)
        try context.delete(model: Meter.self)
        try context.delete(model: Building.self)
        try context.save()
    }
}
