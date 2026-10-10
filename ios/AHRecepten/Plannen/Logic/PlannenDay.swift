import Foundation

/// Dag op het wensen-scherm: open om te plannen, of alleen-lezen (al gepland of voorbij).
struct PlannenDay: Identifiable, Equatable, Sendable {
    var id: String { date }
    let date: String
    /// Wat er al staat (leeg = nog niets).
    let taken: String
    let isPast: Bool

    var isWeekend: Bool { (KiezenDates.weekdayIndex(date) ?? 0) >= 5 }
    var isOpen: Bool { taken.isEmpty && !isPast }
    var label: String { KiezenDates.label(date) }

    /// Zeven dagen vanaf `monday`, met wat er al gepland is.
    static func week(monday: String, today: String, entries: [PlanItem]) -> [PlannenDay] {
        (0..<7).map { offset in
            let date = KiezenDates.add(monday, offset)
            let titles = entries.filter { $0.date == date }.map(\.title).filter { !$0.isEmpty }
            let taken = entries.contains { $0.date == date } ? (titles.first ?? "Gepland") : ""
            return PlannenDay(date: date, taken: taken, isPast: date < today)
        }
    }
}
