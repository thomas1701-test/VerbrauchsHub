import Foundation
import SwiftUI

enum Formatting {
    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.locale = .current
        return f
    }()

    static let counter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        f.locale = .current
        return f
    }()

    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    static let percent: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        f.multiplier = 1
        f.locale = .current
        return f
    }()

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = .current
        return f
    }()

    static let dateShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        f.locale = .current
        return f
    }()

    static func amount(_ value: Decimal, unit: String, fractionDigits: Int = 1) -> String {
        decimal.minimumFractionDigits = fractionDigits
        decimal.maximumFractionDigits = fractionDigits
        let n = decimal.string(from: value as NSDecimalNumber) ?? "\(value)"
        return "\(n) \(unit)"
    }

    static func counter(_ value: Decimal, unit: String) -> String {
        let n = counter.string(from: value as NSDecimalNumber) ?? "\(value)"
        return "\(n) \(unit)"
    }

    static func currency(_ value: Decimal) -> String {
        currency.string(from: value as NSDecimalNumber) ?? "\(value) €"
    }

    static func percent(_ value: Decimal) -> String {
        let n = percent.string(from: value as NSDecimalNumber) ?? "\(value)%"
        return n
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
