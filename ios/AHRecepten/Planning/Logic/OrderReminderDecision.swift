import Foundation

/// Wat er met de lokale besteldag-herinnering moet gebeuren.
enum OrderReminderDecision: Equatable {
    /// (Opnieuw) inplannen op dit moment met deze tekst.
    case schedule(fireDate: Date, body: String)
    /// Geen herinnering (uit, week compleet, of het moment is al voorbij).
    case cancel
}
