import Foundation
import SwiftData

/// The one SwiftData container, shared by the app and its App Intents.
enum AppDataStore {
    static let container: ModelContainer = {
        do {
            let schema = Schema([
                Building.self,
                Meter.self,
                Reading.self,
                Tariff.self,
                AdvancePayment.self,
                Contract.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

/// Requests from outside the view hierarchy (Siri, Shortcuts) that the UI picks up.
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    /// Meter whose "new reading" sheet should open.
    var addReadingMeterID: UUID?
}
