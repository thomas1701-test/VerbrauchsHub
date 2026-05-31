import Foundation

enum PeriodGranularity: String, CaseIterable, Identifiable, Hashable {
    case day, week, month, quarter, year

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .day: return String(localized: "Tag")
        case .week: return String(localized: "Woche")
        case .month: return String(localized: "Monat")
        case .quarter: return String(localized: "Quartal")
        case .year: return String(localized: "Jahr")
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .quarter: return .quarter
        case .year: return .year
        }
    }

    /// Returns the start date of the period containing `date`.
    func startDate(containing date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        case .quarter:
            let comps = calendar.dateComponents([.year, .month], from: date)
            let month = comps.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            return calendar.date(from: DateComponents(year: comps.year, month: quarterStartMonth, day: 1)) ?? date
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    /// Returns the end (exclusive) of the period starting at `start`.
    func endDate(after start: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .quarter:
            return calendar.date(byAdding: .month, value: 3, to: start) ?? start
        case .year:
            return calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }

    /// Returns consecutive periods from `start` (inclusive) to `end` (exclusive).
    func periods(from start: Date, to end: Date, calendar: Calendar = .current) -> [Period] {
        var result: [Period] = []
        var cursor = startDate(containing: start, calendar: calendar)
        while cursor < end {
            let next = endDate(after: cursor, calendar: calendar)
            result.append(Period(granularity: self, start: cursor, end: next))
            cursor = next
        }
        return result
    }

    func label(for start: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        switch self {
        case .day:
            formatter.dateFormat = "dd.MM."
        case .week:
            let comps = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: start)
            return "KW \(comps.weekOfYear ?? 0)/\(String(comps.yearForWeekOfYear ?? 0).suffix(2))"
        case .month:
            formatter.dateFormat = "MMM yy"
        case .quarter:
            let comps = calendar.dateComponents([.month, .year], from: start)
            let q = ((comps.month ?? 1) - 1) / 3 + 1
            return "Q\(q) \(comps.year ?? 0)"
        case .year:
            formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: start)
    }
}

struct Period: Hashable, Identifiable {
    let granularity: PeriodGranularity
    let start: Date
    let end: Date

    var id: String { "\(granularity.rawValue)-\(start.timeIntervalSince1970)" }

    var displayLabel: String { granularity.label(for: start) }
}
