import Foundation

/// Bepaalt de lokale herinnering "het weekmenu voor volgende week is nog niet compleet".
/// Puur (geen notificatie-API), zodat het te testen is.
enum OrderReminderPlanner {
    static let identifier = "miso.order-day-reminder"
    static let title = "Weekmenu volgende week"
    /// Tijdstip op de avond vóór de besteldag.
    static let hour = 19

    static func body(planned: Int, total: Int) -> String {
        "Het weekmenu voor volgende week is nog niet compleet (\(planned)/\(total))"
    }

    /// - Parameters:
    ///   - enabled: "Herinner me voor de besteldag" staat aan.
    ///   - status: laatste `next-week-status` (nil = onbekend: niets inplannen).
    ///   - now: huidig moment; `status.daysUntilOrder` telt vanaf deze dag.
    static func decide(enabled: Bool, status: NextWeekStatus?, now: Date, calendar: Calendar) -> OrderReminderDecision {
        guard enabled, let status, !status.isComplete, status.daysUntilOrder >= 0 else { return .cancel }
        let today = calendar.startOfDay(for: now)
        guard let orderDay = calendar.date(byAdding: .day, value: status.daysUntilOrder, to: today),
              let evening = calendar.date(byAdding: .day, value: -1, to: orderDay),
              let fireDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: evening),
              fireDate > now
        else { return .cancel }
        return .schedule(fireDate: fireDate, body: body(planned: status.progressPlanned, total: status.progressTotal))
    }
}
