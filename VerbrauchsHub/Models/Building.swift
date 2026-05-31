import Foundation
import SwiftData

@Model
final class Building {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String?
    var iconName: String
    var colorHex: String
    var notes: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Meter.building)
    var meters: [Meter] = []

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        iconName: String = "house.fill",
        colorHex: String = "#1E88E5",
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.iconName = iconName
        self.colorHex = colorHex
        self.notes = notes
        self.createdAt = createdAt
    }
}
