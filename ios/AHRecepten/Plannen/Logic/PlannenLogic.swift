import Foundation

/// Pure regels van het Plannen-scherm (getest in PlannenLogicTests).
enum PlannenLogic {
    /// Maandag van de week waar `date` in valt.
    static func monday(of date: String) -> String {
        KiezenDates.add(date, -(KiezenDates.weekdayIndex(date) ?? 0))
    }

    /// Zelfde regel als `default_week` op de server: ma-wo met nog open doordeweekse dagen vanaf vandaag
    /// = deze week; anders volgende week (waarvoor je nu bestelt).
    static func defaultWeek(today: String, takenDates: Set<String>) -> String {
        let thisMonday = monday(of: today)
        let weekday = KiezenDates.weekdayIndex(today) ?? 0
        let openWeekdays = (0..<5).map { KiezenDates.add(thisMonday, $0) }
            .filter { $0 >= today && !takenDates.contains($0) }
        if weekday <= 2 && !openWeekdays.isEmpty { return thisMonday }
        return KiezenDates.add(thisMonday, 7)
    }

    /// Wensen van de open dagen, zoals `collect()` op /plannen.
    static func collect(_ wishes: [String: WishInput], days: [PlannenDay]) -> [String: String] {
        var out: [String: String] = [:]
        for day in days where day.isOpen {
            if let value = wishes[day.date]?.value { out[day.date] = value }
        }
        return out
    }

    /// Wensen uit de zin overnemen op open dagen. Geeft de datums terug die zijn ingevuld.
    @discardableResult
    static func merge(_ parsed: [String: String], into wishes: inout [String: WishInput],
                      days: [PlannenDay]) -> [String] {
        let open = Set(days.filter(\.isOpen).map(\.date))
        var filled: [String] = []
        for (date, value) in parsed.sorted(by: { $0.key < $1.key }) where open.contains(date) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            wishes[date] = WishInput(serverValue: trimmed)
            filled.append(date)
        }
        return filled
    }

    /// Lege open doordeweekse dagen op "Geen idee" zetten (Miso kiest), voor wie snel wil.
    static func fillEmptyWeekdays(_ wishes: inout [String: WishInput], days: [PlannenDay], with chip: WishChip = .vrij) {
        for day in days where day.isOpen && !day.isWeekend && (wishes[day.date]?.isEmpty ?? true) {
            wishes[day.date] = WishInput(chip: chip)
        }
    }

    /// Minuten uit "25 min", "1 uur", "1 uur 15 min" (zoals `wishes.minutes` op de server). nil = onbekend.
    static func minutes(_ totalTime: String) -> Int? {
        let lower = totalTime.lowercased()
        let numbers = lower.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = numbers.first else { return nil }
        if lower.contains("uur") && first < 5 {
            let extra = numbers.count > 1 ? numbers[1] : 0
            return first * 60 + extra
        }
        return first
    }
}
