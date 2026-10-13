import Foundation
import UserNotifications

/// Vrijdag om 17:00: "N recepten van jullie zitten volgende week in de bonus" (lokale melding, standaard aan,
/// uit te zetten bij Meer). Wordt bij elke verversing van de next-week-status opnieuw bepaald.
@MainActor
enum BonusHintReminder {
    static let enabledKey = "bonusHintEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func refresh(status: NextWeekStatus) async {
        let center = UNUserNotificationCenter.current()
        let decision = BonusHintPlanner.decide(enabled: isEnabled, hint: status.bonusHint, nextWeek: status.week,
                                               now: .now, calendar: .current)
        switch decision {
        case .cancel:
            cancel()
        case .schedule(let fireDate, let body):
            let auth = await center.notificationSettings().authorizationStatus
            guard auth == .authorized || auth == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = BonusHintPlanner.title
            content.body = body
            content.sound = .default
            content.userInfo = ["tab": "plannen"]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            // Zelfde id: een nieuwe aanvraag vervangt de vorige.
            try? await center.add(UNNotificationRequest(identifier: BonusHintPlanner.identifier, content: content,
                                                        trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [BonusHintPlanner.identifier])
    }
}
