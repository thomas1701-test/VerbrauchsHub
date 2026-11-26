import XCTest
import SwiftData
@testable import VerbrauchsHub

@MainActor
final class DataTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Building.self, Meter.self, Reading.self, Tariff.self, AdvancePayment.self, Contract.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        return ModelContext(container)
    }

    func testMigrationCopiesLegacyAdvanceOnce() throws {
        let context = try makeContext()
        let meter = Meter(type: .electricity, createdAt: date(2025, 1, 1))
        meter.advancePaymentPerMonth = 80
        meter.billingStartDate = date(2024, 3, 1)
        context.insert(meter)
        context.insert(Reading(meter: meter, date: date(2024, 1, 15), value: 0))
        DataMigration.run(context)
        DataMigration.run(context)
        XCTAssertEqual(meter.advancePayments.count, 1)
        XCTAssertEqual(meter.advancePayments.first?.amountPerMonth, 80)
        // Earliest of first reading, billing start and creation.
        XCTAssertEqual(meter.advancePayments.first?.validFrom, date(2024, 1, 15))
    }

    func testMigrationSkipsMetersWithoutAdvance() throws {
        let context = try makeContext()
        let meter = Meter(type: .water)
        context.insert(meter)
        DataMigration.run(context)
        XCTAssertTrue(meter.advancePayments.isEmpty)
    }

    // MARK: - Export / Import

    func testRoundtripKeepsContractsAdvancesAndMeterChange() throws {
        let source = try makeContext()
        let meter = Meter(type: .electricity)
        source.insert(meter)
        source.insert(Reading(meter: meter, date: date(2025, 1, 1), value: 1000))
        source.insert(Reading(meter: meter, date: date(2025, 6, 1), value: 0, previousMeterFinalValue: 1400))
        let contract = Contract(meter: meter, provider: "Stadtwerke", startDate: date(2025, 1, 1))
        contract.minimumTermEnd = date(2026, 1, 1)
        contract.noticePeriodValue = 6
        contract.noticeUnit = .weeks
        contract.priceGuaranteeUntil = date(2025, 12, 31)
        source.insert(contract)
        let loose = Tariff(meter: meter, pricePerUnit: Decimal(string: "0.30")!, validFrom: date(2024, 1, 1))
        let inContract = Tariff(meter: meter, pricePerUnit: Decimal(string: "0.35")!, validFrom: date(2025, 1, 1))
        inContract.contract = contract
        source.insert(loose)
        source.insert(inContract)
        source.insert(AdvancePayment(meter: meter, amountPerMonth: 90, validFrom: date(2024, 1, 1)))
        source.insert(AdvancePayment(meter: meter, amountPerMonth: 110, validFrom: date(2025, 1, 1)))
        ValidityChain.relink(meter.tariffs)
        ValidityChain.relink(meter.advancePayments)
        try source.save()

        let snapshot = ExportService.makeSnapshot(
            buildings: [], meters: [meter], readings: meter.readings, tariffs: meter.tariffs,
            contracts: meter.contracts, advancePayments: meter.advancePayments
        )
        let data = try Data(contentsOf: ExportService.writeJSON(snapshot))

        let target = try makeContext()
        _ = try ImportService.importSnapshot(data: data, into: target, strategy: .replace)
        let imported = try XCTUnwrap(target.fetch(FetchDescriptor<Meter>()).first)
        XCTAssertEqual(imported.contracts.count, 1)
        XCTAssertEqual(imported.contracts.first?.provider, "Stadtwerke")
        XCTAssertEqual(imported.contracts.first?.noticeUnit, .weeks)
        XCTAssertEqual(imported.contracts.first?.priceGuaranteeUntil, date(2025, 12, 31))
        XCTAssertEqual(imported.tariffs.count, 2)
        XCTAssertEqual(imported.tariffs.first { $0.pricePerUnit == Decimal(string: "0.35")! }?.contract?.provider, "Stadtwerke")
        XCTAssertNil(imported.tariffs.first { $0.pricePerUnit == Decimal(string: "0.30")! }?.contract)
        XCTAssertEqual(imported.tariffs.first { $0.pricePerUnit == Decimal(string: "0.30")! }?.validTo, date(2025, 1, 1))
        XCTAssertEqual(imported.advancePayments.map(\.amountPerMonth).sorted(), [90, 110])
        XCTAssertEqual(imported.advancePayments.first { $0.amountPerMonth == 90 }?.validTo, date(2025, 1, 1))
        XCTAssertEqual(imported.readings.first { $0.isMeterChange }?.previousMeterFinalValue, 1400)
    }

    func testImportsLegacyBackup() throws {
        let json = """
        {
          "schemaVersion": 1,
          "exportedAt": "2025-08-01T10:00:00Z",
          "buildings": [],
          "meters": [{
            "id": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00", "typeRaw": "electricity", "unitRaw": "kWh",
            "iconName": "bolt.fill", "colorHex": "#FFB300", "reminderEnabled": false,
            "createdAt": "2025-01-01T00:00:00Z", "advancePaymentPerMonth": 70, "billingStartDate": "2025-01-01T00:00:00Z"
          }],
          "readings": [{
            "id": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E01", "meterID": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00",
            "date": "2025-01-01T00:00:00Z", "value": 0, "createdAt": "2025-01-01T00:00:00Z"
          }],
          "tariffs": [{
            "id": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E02", "meterID": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00",
            "pricePerUnit": 0.3, "baseFeePerMonth": 10, "validFrom": "2024-01-01T00:00:00Z", "createdAt": "2024-01-01T00:00:00Z"
          }]
        }
        """
        let context = try makeContext()
        _ = try ImportService.importSnapshot(data: Data(json.utf8), into: context, strategy: .replace)
        let meter = try XCTUnwrap(context.fetch(FetchDescriptor<Meter>()).first)
        XCTAssertEqual(meter.advancePayments.count, 1)
        XCTAssertEqual(meter.advancePayments.first?.amountPerMonth, 70)
        XCTAssertEqual(meter.tariffs.count, 1)
        XCTAssertNil(meter.tariffs.first?.contract)
    }

    // MARK: - Review fixes

    func testMergingOldBackupKeepsMeterChangeAndContract() throws {
        let context = try makeContext()
        let meterID = UUID(uuidString: "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00")!
        let meter = Meter(id: meterID, type: .electricity)
        context.insert(meter)
        let reading = Reading(id: UUID(uuidString: "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E01")!, meter: meter, date: date(2025, 1, 1), value: 0, previousMeterFinalValue: 900)
        context.insert(reading)
        let contract = Contract(meter: meter, provider: "Stadtwerke", startDate: date(2024, 1, 1))
        context.insert(contract)
        let tariff = Tariff(id: UUID(uuidString: "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E02")!, meter: meter, pricePerUnit: Decimal(string: "0.3")!, validFrom: date(2024, 1, 1))
        tariff.contract = contract
        context.insert(tariff)
        try context.save()

        let json = """
        {
          "schemaVersion": 1, "exportedAt": "2025-08-01T10:00:00Z", "buildings": [],
          "meters": [{ "id": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00", "typeRaw": "electricity", "unitRaw": "kWh",
            "iconName": "bolt.fill", "colorHex": "#FFB300", "reminderEnabled": false, "createdAt": "2025-01-01T00:00:00Z" }],
          "readings": [{ "id": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E01", "meterID": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00",
            "date": "2025-01-01T00:00:00Z", "value": 0, "createdAt": "2025-01-01T00:00:00Z" }],
          "tariffs": [{ "id": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E02", "meterID": "6F1C7B8E-1D2A-4E2B-9C51-7A0B3C2D1E00",
            "pricePerUnit": 0.3, "baseFeePerMonth": 0, "validFrom": "2024-01-01T00:00:00Z", "createdAt": "2024-01-01T00:00:00Z" }]
        }
        """
        _ = try ImportService.importSnapshot(data: Data(json.utf8), into: context, strategy: .merge)
        XCTAssertEqual(reading.previousMeterFinalValue, 900)
        XCTAssertEqual(tariff.contract?.provider, "Stadtwerke")
    }
}
