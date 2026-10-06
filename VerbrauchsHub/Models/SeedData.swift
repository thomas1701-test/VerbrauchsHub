import Foundation
import SwiftData

enum SeedData {
    /// Launch argument that fills an empty store with demo data (used for App Store screenshots).
    static let launchArgument = "-seedDemoData"

    /// Inserts demo data only when explicitly requested via launch argument.
    /// Real users start with the onboarding and can opt into demo data there.
    static func seedIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        let buildingCount = (try? context.fetchCount(FetchDescriptor<Building>())) ?? 0
        guard buildingCount == 0 else { return }
        insertDemoData(context)
    }

    static func insertDemoData(_ context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let tariffStart = calendar.date(byAdding: .year, value: -3, to: now)!

        let haus = Building(name: "Mein Haus", address: "Sonnenweg 12", iconName: "house.fill", colorHex: "#1E88E5")
        let fewo = Building(name: "Ferienwohnung", address: "Strandallee 4", iconName: "building.fill", colorHex: "#00ACC1", createdAt: now.addingTimeInterval(1))
        context.insert(haus)
        context.insert(fewo)

        let strom = Meter(building: haus, type: .electricity, createdAt: now)
        let pv = Meter(building: haus, type: .electricityFeedIn, createdAt: now.addingTimeInterval(1))
        let eigen = Meter(building: haus, type: .electricitySelfConsumption, createdAt: now.addingTimeInterval(2))
        let gas = Meter(building: haus, type: .gas, createdAt: now.addingTimeInterval(3))
        let wasser = Meter(building: haus, type: .water, createdAt: now.addingTimeInterval(4))
        let fewoStrom = Meter(building: fewo, type: .electricity, createdAt: now.addingTimeInterval(5))
        let fewoWasser = Meter(building: fewo, type: .water, createdAt: now.addingTimeInterval(6))
        [strom, pv, eigen, gas, wasser, fewoStrom, fewoWasser].forEach { context.insert($0) }

        context.insert(Tariff(meter: strom, pricePerUnit: Decimal(string: "0.34")!, baseFeePerMonth: Decimal(string: "12.50")!, validFrom: tariffStart))
        context.insert(Tariff(meter: pv, pricePerUnit: 0, baseFeePerMonth: 0, feedInPricePerUnit: Decimal(string: "0.082")!, validFrom: tariffStart))
        context.insert(Tariff(meter: gas, pricePerUnit: Decimal(string: "0.11")!, baseFeePerMonth: Decimal(string: "14.90")!, validFrom: tariffStart))
        context.insert(Tariff(meter: wasser, pricePerUnit: Decimal(string: "4.35")!, baseFeePerMonth: Decimal(string: "6.00")!, validFrom: tariffStart))
        context.insert(Tariff(meter: fewoStrom, pricePerUnit: Decimal(string: "0.36")!, baseFeePerMonth: Decimal(string: "10.00")!, validFrom: tariffStart))
        context.insert(Tariff(meter: fewoWasser, pricePerUnit: Decimal(string: "4.35")!, baseFeePerMonth: Decimal(string: "6.00")!, validFrom: tariffStart))

        // Monthly readings for the last 24 months (enables "Vorjahr" comparisons).
        // season: +1 = peak in winter, -1 = peak in summer, 0 = flat.
        seedReadings(meter: strom, startValue: 41_230, perMonth: 290, season: 0.25, context: context)
        seedReadings(meter: pv, startValue: 12_480, perMonth: 480, season: -0.8, context: context)
        seedReadings(meter: eigen, startValue: 5_310, perMonth: 210, season: -0.7, context: context)
        seedReadings(meter: gas, startValue: 18_940, perMonth: 110, season: 0.85, context: context)
        seedReadings(meter: wasser, startValue: 1_204, perMonth: 9.5, season: -0.15, context: context)
        seedReadings(meter: fewoStrom, startValue: 9_870, perMonth: 95, season: -0.35, context: context)
        seedReadings(meter: fewoWasser, startValue: 312, perMonth: 3.2, season: -0.5, context: context)

        try? context.save()
    }

    /// Readings are cumulative meter values, so every month adds a positive increment.
    private static func seedReadings(meter: Meter, startValue: Double, perMonth: Double, season: Double, context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        // Fixed jitter pattern keeps the demo data (and screenshots) reproducible.
        let jitter: [Double] = [1.04, 0.96, 1.08, 0.93, 1.01, 1.06, 0.95, 1.03, 0.98, 1.07, 0.94, 1.02]
        var value = startValue
        for i in stride(from: 24, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            if i < 24 {
                let month = Double(calendar.component(.month, from: date))
                let seasonal = 1 + season * cos((month - 1) / 12 * 2 * .pi)
                value += perMonth * max(seasonal, 0.1) * jitter[i % jitter.count]
            }
            let rounded = (value * 10).rounded() / 10
            context.insert(Reading(meter: meter, date: date, value: Decimal(rounded)))
        }
    }
}
