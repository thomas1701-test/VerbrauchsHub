import Foundation
import SwiftData

enum SeedData {
    /// Inserts demo data when the store is empty so first launch isn't blank.
    static func seedIfNeeded(_ context: ModelContext) {
        let buildingCount = (try? context.fetchCount(FetchDescriptor<Building>())) ?? 0
        guard buildingCount == 0 else { return }

        let calendar = Calendar.current
        let now = Date()

        let haus = Building(name: "Mein Haus", address: "Musterstraße 1", iconName: "house.fill", colorHex: "#1E88E5")
        context.insert(haus)

        let strom = Meter(building: haus, type: .electricity)
        let pv = Meter(building: haus, type: .electricityFeedIn)
        let wasser = Meter(building: haus, type: .water)
        let gas = Meter(building: haus, type: .gas)
        [strom, pv, wasser, gas].forEach { context.insert($0) }

        // Tarife
        context.insert(Tariff(meter: strom, pricePerUnit: Decimal(0.36), baseFeePerMonth: Decimal(12.50), validFrom: calendar.date(byAdding: .year, value: -1, to: now)!))
        context.insert(Tariff(meter: pv, pricePerUnit: 0, baseFeePerMonth: 0, feedInPricePerUnit: Decimal(0.082), validFrom: calendar.date(byAdding: .year, value: -1, to: now)!))
        context.insert(Tariff(meter: wasser, pricePerUnit: Decimal(2.85), baseFeePerMonth: Decimal(5.0), validFrom: calendar.date(byAdding: .year, value: -1, to: now)!))
        context.insert(Tariff(meter: gas, pricePerUnit: Decimal(0.12), baseFeePerMonth: Decimal(15.0), validFrom: calendar.date(byAdding: .year, value: -1, to: now)!))

        // Beispiel-Ablesungen monatlich rückwirkend 14 Monate
        seedReadings(meter: strom, startValue: 18_000, perMonth: 280, context: context)
        seedReadings(meter: pv, startValue: 6_500, perMonth: 420, context: context)
        seedReadings(meter: wasser, startValue: 980, perMonth: 12, context: context)
        seedReadings(meter: gas, startValue: 21_400, perMonth: 95, context: context)

        try? context.save()
    }

    private static func seedReadings(meter: Meter, startValue: Decimal, perMonth: Decimal, context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        for i in stride(from: 14, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            // jitter +- 15 %
            let jitter = Decimal(Double.random(in: 0.85...1.15))
            let increment = perMonth * jitter * Decimal(14 - i)
            let value = startValue + increment
            context.insert(Reading(meter: meter, date: date, value: value))
        }
    }
}
