import Foundation

/// Something that applies from `validFrom` until `validTo` (open-ended if nil), such as a
/// tariff or an advance payment.
protocol ValidityPeriod: AnyObject {
    var validFrom: Date { get }
    var validTo: Date? { get set }
}

enum ValidityStatus {
    /// Starts in the future, e.g. a contract already signed for next year.
    case planned
    case current
    case ended
}

extension ValidityPeriod {
    func status(on date: Date) -> ValidityStatus {
        if date < validFrom { return .planned }
        if let validTo, date >= validTo { return .ended }
        return .current
    }

    func isActive(on date: Date) -> Bool {
        status(on: date) == .current
    }
}

enum ValidityChain {
    /// Chains the entries of one meter without gaps or overlaps: each ends where the next one
    /// starts, the latest stays open. Call after adding, editing or deleting an entry, passing
    /// the entries that remain.
    static func relink<T: ValidityPeriod>(_ items: [T]) {
        let sorted = items.sorted { $0.validFrom < $1.validFrom }
        for (index, item) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].validFrom : nil
            if item.validTo != next { item.validTo = next }
        }
    }
}
