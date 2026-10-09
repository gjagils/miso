import Foundation

/// Datums als "YYYY-MM-DD"-strings, zoals de server ze stuurt.
enum KiezenDates {
    private static let days = ["Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag", "Zondag"]
    private static let months = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    static func parse(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func iso(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static var today: String { iso(Date()) }

    static func add(_ s: String, _ n: Int) -> String {
        guard let d = parse(s), let r = calendar.date(byAdding: .day, value: n, to: d) else { return s }
        return iso(r)
    }

    /// "Maandag 6 okt"
    static func label(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        let c = calendar.dateComponents([.weekday, .day, .month], from: d)
        let weekday = ((c.weekday ?? 2) + 5) % 7
        return "\(days[weekday]) \(c.day ?? 0) \(months[(c.month ?? 1) - 1])"
    }

    /// 0 = maandag … 6 = zondag (nil bij een ongeldige datum).
    static func weekdayIndex(_ s: String) -> Int? {
        guard let d = parse(s) else { return nil }
        return (calendar.component(.weekday, from: d) + 5) % 7
    }

    /// Dag van de maand (6 voor "2025-10-06").
    static func dayOfMonth(_ s: String) -> Int? {
        parse(s).map { calendar.component(.day, from: $0) }
    }

    /// "Maandag" (eerste woord van het label).
    static func weekdayName(_ s: String) -> String {
        weekdayIndex(s).map { days[$0] } ?? s
    }

    /// "6 okt"
    static func short(_ s: String) -> String {
        label(s).split(separator: " ").dropFirst().joined(separator: " ")
    }
}
