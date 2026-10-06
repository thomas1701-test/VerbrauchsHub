import AppIntents
import Foundation
import SwiftData

struct MeterEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Zähler"
    static let defaultQuery = MeterQuery()

    let id: UUID
    let name: String
    let building: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: building.map { "\($0)" })
    }

    init(meter: Meter) {
        id = meter.id
        name = meter.displayName
        building = meter.building?.name
    }
}

struct MeterQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MeterEntity] {
        try allMeters().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MeterEntity] {
        try allMeters()
    }

    @MainActor
    private func allMeters() throws -> [MeterEntity] {
        let context = AppDataStore.container.mainContext
        let meters = try context.fetch(FetchDescriptor<Meter>())
        return meters.sorted { $0.createdAt < $1.createdAt }.map(MeterEntity.init)
    }
}

/// Opens the app with the entry form for a meter.
struct AddReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Zählerstand erfassen"
    static let description = IntentDescription("Öffnet VerbrauchsHub mit einer neuen Ablesung für den gewählten Zähler.")
    static let openAppWhenRun = true

    @Parameter(title: "Zähler", requestValueDialog: "Für welchen Zähler?")
    var meter: MeterEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.addReadingMeterID = meter.id
        return .result()
    }
}

struct VerbrauchsHubShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReadingIntent(),
            phrases: [
                "Zählerstand in \(.applicationName) erfassen",
                "Ablesung in \(.applicationName) eintragen",
                "\(.applicationName) Zählerstand",
            ],
            shortTitle: "Zählerstand erfassen",
            systemImageName: "gauge.with.dots.needle.bottom.50percent"
        )
    }
}
