import Foundation
import SwiftData

/// Brings data from older versions up to date. Safe to run any number of times.
enum DataMigration {
    @MainActor
    static func run(_ context: ModelContext) {
        let meters = (try? context.fetch(FetchDescriptor<Meter>())) ?? []
        var changed = false
        for meter in meters {
            // 1.1 stored a single advance payment on the meter; 1.2 keeps a history.
            if let legacy = meter.advancePaymentPerMonth, legacy > 0, meter.advancePayments.isEmpty {
                let firstReading = meter.readings.map(\.date).min()
                let start = [firstReading, meter.billingStartDate, meter.createdAt].compactMap { $0 }.min() ?? meter.createdAt
                context.insert(AdvancePayment(meter: meter, amountPerMonth: legacy, validFrom: start))
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
