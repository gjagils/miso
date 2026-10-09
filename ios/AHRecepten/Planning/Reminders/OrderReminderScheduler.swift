import Foundation
import UserNotifications

/// Lokale herinnering voor de besteldag (geen server-push).
///
/// Staat standaard uit. Aanzetten gebeurt in Meer; pas dan vraagt de app (één keer) toestemming.
/// Bij elke verversing van de next-week-status wordt de herinnering opnieuw ingepland of weggehaald.
@MainActor
enum OrderReminderScheduler {
    /// `@AppStorage`-sleutel voor "Herinner me voor de besteldag".
    static let enabledKey = "orderReminderEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Status ophalen en de herinnering bijwerken. Fouten zijn niet erg: de volgende verversing probeert het opnieuw.
    static func refresh(api: API) async {
        guard isEnabled, let status = try? await api.nextWeekStatus() else {
            if !isEnabled { cancel() }
            return
        }
        await apply(status)
    }

    static func apply(_ status: NextWeekStatus?) async {
        let decision = OrderReminderPlanner.decide(enabled: isEnabled, status: status, now: .now, calendar: .current)
        switch decision {
        case .cancel:
            cancel()
        case .schedule(let fireDate, let body):
            await schedule(at: fireDate, body: body)
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [OrderReminderPlanner.identifier])
    }

    /// Mag de app meldingen sturen? (zonder te vragen)
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Vraagt toestemming (iOS toont dit maar één keer). Geeft true als meldingen mogen.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private static func schedule(at fireDate: Date, body: String) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = OrderReminderPlanner.title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        // Zelfde id: een nieuwe aanvraag vervangt de vorige.
        let request = UNNotificationRequest(identifier: OrderReminderPlanner.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
