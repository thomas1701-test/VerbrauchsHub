import Foundation
import SwiftUI

enum MeterType: String, Codable, CaseIterable, Identifiable, Hashable {
    case electricity
    case electricityFeedIn
    case electricitySelfConsumption
    case water
    case gas
    case heating
    case custom

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .electricity: return String(localized: "Strom (Bezug)")
        case .electricityFeedIn: return String(localized: "PV-Einspeisung")
        case .electricitySelfConsumption: return String(localized: "PV-Eigenverbrauch")
        case .water: return String(localized: "Wasser")
        case .gas: return String(localized: "Gas")
        case .heating: return String(localized: "Wärme")
        case .custom: return String(localized: "Sonstiger Zähler")
        }
    }

    var defaultUnit: Unit {
        switch self {
        case .electricity, .electricityFeedIn, .electricitySelfConsumption, .heating:
            return .kWh
        case .water, .gas:
            return .cubicMeter
        case .custom:
            return .custom
        }
    }

    var defaultIconName: String {
        switch self {
        case .electricity: return "bolt.fill"
        case .electricityFeedIn: return "sun.max.fill"
        case .electricitySelfConsumption: return "house.fill"
        case .water: return "drop.fill"
        case .gas: return "flame.fill"
        case .heating: return "thermometer.medium"
        case .custom: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .electricity: return "#FFB300"          // amber
        case .electricityFeedIn: return "#43A047"    // green
        case .electricitySelfConsumption: return "#7CB342" // light green
        case .water: return "#039BE5"                 // blue
        case .gas: return "#E53935"                   // red
        case .heating: return "#FB8C00"               // orange
        case .custom: return "#8E24AA"                // purple
        }
    }

    var isFeedIn: Bool { self == .electricityFeedIn }
}

enum Unit: String, Codable, CaseIterable, Identifiable, Hashable {
    case kWh
    case cubicMeter
    case liter
    case custom

    var id: String { rawValue }

    func localizedLabel(custom: String?) -> String {
        switch self {
        case .kWh: return "kWh"
        case .cubicMeter: return "m³"
        case .liter: return "L"
        case .custom: return custom?.isEmpty == false ? custom! : "—"
        }
    }
}
