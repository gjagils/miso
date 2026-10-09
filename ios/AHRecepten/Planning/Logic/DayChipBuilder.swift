import Foundation

/// Dagchips voor het Inplannen-scherm: 7 dagen vanaf `start`, bezette dagen gemarkeerd.
/// Zelfde regels als `backend/app/static/plan.js` (renderDays/open). Puur: geen netwerk, geen UI.
enum DayChipBuilder {
    private static let short = ["ma", "di", "wo", "do", "vr", "za", "zo"]

    /// De 7 datums vanaf `start`.
    static func dates(start: String) -> [String] {
        (0..<7).map { KiezenDates.add(start, $0) }
    }

    /// - Parameter ignoring: regel die verplaatst wordt; telt niet als bezet op zijn eigen dag.
    static func chips(start: String, today: String, entries: [PlanItem], ignoring entryID: Int? = nil) -> [DayChip] {
        var busy: [String: [String]] = [:]
        for entry in entries {
            if let entryID, entry.entryId == entryID { continue }
            busy[entry.date, default: []].append(entry.title)
        }
        return dates(start: start).map { date in
            DayChip(date: date,
                    weekdayShort: KiezenDates.weekdayIndex(date).map { short[$0] } ?? "",
                    dayNumber: KiezenDates.dayOfMonth(date) ?? 0,
                    occupied: busy[date] ?? [],
                    isPast: date < today,
                    isToday: date == today)
        }
    }

    /// Eerste chip en gekozen dag bij het openen.
    /// - Een gekozen dag buiten het venster schuift het venster naar die dag.
    /// - Zonder dag (en als er iets ingepland moet worden): het begin van het venster, of vandaag als dat later is.
    static func initialWindow(start: String?, date: String?, today: String, chooseDefault: Bool = true) -> (start: String, date: String?) {
        var first = start ?? today
        if let date, date < first || date > KiezenDates.add(first, 6) { first = date }
        if let date { return (first, date) }
        guard chooseDefault else { return (first, nil) }
        return (first, max(first, today))
    }

    /// Regel onder de chips: "Maandag 12 okt: er staat al Lasagne" / "Kies een dag."
    static func info(for date: String?, chips: [DayChip]) -> String {
        guard let date else { return "Kies een dag." }
        let label = KiezenDates.label(date)
        guard let chip = chips.first(where: { $0.date == date }), chip.isOccupied else { return label }
        return "\(label): er staat al \(chip.occupied.joined(separator: ", "))"
    }

    /// Eerste vrije dag vanaf vandaag in een week (voor "Plan in" vanuit de vriezer).
    static func firstFreeDay(week: String, today: String, entries: [PlanItem]) -> String? {
        let taken = Set(entries.map(\.date))
        return dates(start: week).first { $0 >= today && !taken.contains($0) }
    }
}
