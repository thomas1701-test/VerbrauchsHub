import Foundation
import SwiftData

struct ExportSnapshot: Codable {
    var schemaVersion: Int = 1
    var exportedAt: Date
    var buildings: [BuildingDTO]
    var meters: [MeterDTO]
    var readings: [ReadingDTO]
    var tariffs: [TariffDTO]
}

struct BuildingDTO: Codable {
    let id: UUID
    let name: String
    let address: String?
    let iconName: String
    let colorHex: String
    let notes: String?
    let createdAt: Date
}

struct MeterDTO: Codable {
    let id: UUID
    let buildingID: UUID?
    let typeRaw: String
    let customName: String?
    let unitRaw: String
    let unitCustomLabel: String?
    let iconName: String
    let colorHex: String
    let reminderEnabled: Bool
    let reminderDayOfMonth: Int?
    let createdAt: Date
}

struct ReadingDTO: Codable {
    let id: UUID
    let meterID: UUID?
    let date: Date
    let value: Decimal
    let note: String?
    let photoData: Data?
    let createdAt: Date
}

struct TariffDTO: Codable {
    let id: UUID
    let meterID: UUID?
    let pricePerUnit: Decimal
    let baseFeePerMonth: Decimal
    let feedInPricePerUnit: Decimal?
    let validFrom: Date
    let validTo: Date?
    let createdAt: Date
}

enum ExportService {
    static func makeSnapshot(buildings: [Building], meters: [Meter], readings: [Reading], tariffs: [Tariff]) -> ExportSnapshot {
        ExportSnapshot(
            exportedAt: .now,
            buildings: buildings.map {
                BuildingDTO(id: $0.id, name: $0.name, address: $0.address, iconName: $0.iconName, colorHex: $0.colorHex, notes: $0.notes, createdAt: $0.createdAt)
            },
            meters: meters.map {
                MeterDTO(id: $0.id, buildingID: $0.building?.id, typeRaw: $0.typeRaw, customName: $0.customName, unitRaw: $0.unitRaw, unitCustomLabel: $0.unitCustomLabel, iconName: $0.iconName, colorHex: $0.colorHex, reminderEnabled: $0.reminderEnabled, reminderDayOfMonth: $0.reminderDayOfMonth, createdAt: $0.createdAt)
            },
            readings: readings.map {
                ReadingDTO(id: $0.id, meterID: $0.meter?.id, date: $0.date, value: $0.value, note: $0.note, photoData: $0.photoData, createdAt: $0.createdAt)
            },
            tariffs: tariffs.map {
                TariffDTO(id: $0.id, meterID: $0.meter?.id, pricePerUnit: $0.pricePerUnit, baseFeePerMonth: $0.baseFeePerMonth, feedInPricePerUnit: $0.feedInPricePerUnit, validFrom: $0.validFrom, validTo: $0.validTo, createdAt: $0.createdAt)
            }
        )
    }

    static func writeJSON(_ snapshot: ExportSnapshot) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VerbrauchsHub-\(timestamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func writeCSV(meters: [Meter]) throws -> URL {
        var content = ""
        for meter in meters {
            content += "# \(meter.displayName) (\(meter.building?.name ?? "—")) — Einheit: \(meter.unitLabel)\n"
            content += "Datum;Zaehlerstand;Notiz\n"
            for reading in meter.readings.sorted(by: { $0.date < $1.date }) {
                let dateStr = ISO8601DateFormatter().string(from: reading.date)
                let valueStr = NSDecimalNumber(decimal: reading.value).stringValue
                let note = (reading.note ?? "").replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ")
                content += "\(dateStr);\(valueStr);\(note)\n"
            }
            content += "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VerbrauchsHub-\(timestamp()).csv")
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}
