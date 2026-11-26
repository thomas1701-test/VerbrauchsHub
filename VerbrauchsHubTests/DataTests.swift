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
        let schema = Schema([Building.self, Meter.self, Reading.self, Tariff.self, AdvancePayment.self])
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
}
