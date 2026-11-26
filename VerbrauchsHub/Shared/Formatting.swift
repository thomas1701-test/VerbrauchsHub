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

    /// Net cost for display: negative totals (feed-in revenue) are shown as "+x €".
    static func netCost(_ value: Decimal) -> String {
        value < 0 ? "+" + currency(-value) : currency(value)
    }

    static func percent(_ value: Decimal) -> String {
        let n = percent.string(from: value as NSDecimalNumber) ?? "\(value)%"
        return n
    }

    /// Parses user input like "1.234,5", "1234,5" or "1234.5". Rejects trailing garbage
    /// (`Decimal(string:)` alone would silently turn "12abc" into 12).
    /// Value for an input field: German decimal comma, no grouping ("21612,8").
    static func inputString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    static func parseDecimal(_ input: String) -> Decimal? {
        var s = input.filter { !$0.isWhitespace }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard !s.isEmpty,
              s.filter({ $0 == "." }).count <= 1,
              s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
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
