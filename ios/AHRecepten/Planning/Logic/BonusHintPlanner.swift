import Foundation

/// Bepaalt het vrijdagbericht "N recepten zitten volgende week in de bonus" (lokale melding, A5).
/// Puur (geen notificatie-API), zodat het te testen is.
enum BonusHintPlanner {
    static let identifier = "miso.bonus-hint"
    static let title = "Volgende week in de bonus"
    /// Vrijdag om 17:00 (Calendar-weekdag 6).
    static let weekday = 6
    static let hour = 17

    /// - Parameters:
    ///   - enabled: het vrijdagbericht staat aan.
    ///   - hint: laatste bonushint uit `next-week-status` (nil = onbekend).
    ///   - nextWeek: maandag (JJJJ-MM-DD) van de week waar de hint over gaat.
    ///   - now: huidig moment.
    /// Alleen als de eerstvolgende vrijdag nog vóór die maandag valt; anders gaat de hint over een week die al
    /// begonnen is en klopt "volgende week" niet meer.
    static func decide(enabled: Bool, hint: BonusHint?, nextWeek: String, now: Date, calendar: Calendar) -> OrderReminderDecision {
        guard enabled, let hint, hint.isUseful, let monday = parse(nextWeek, calendar: calendar) else { return .cancel }
        var parts = DateComponents()
        parts.weekday = weekday
        parts.hour = hour
        parts.minute = 0
        guard let fireDate = calendar.nextDate(after: now.addingTimeInterval(-1), matching: parts,
                                               matchingPolicy: .nextTime),
              fireDate > now, fireDate < monday
        else { return .cancel }
        return .schedule(fireDate: fireDate, body: hint.message)
    }

    private static func parse(_ iso: String, calendar: Calendar) -> Date? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }
}
