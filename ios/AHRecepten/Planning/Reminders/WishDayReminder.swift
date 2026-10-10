import Foundation
import UserNotifications

/// Elke week op de besteldag om 12:00: "geef je wensen door" (kinderen) of "bekijk de wensen en bestel" (ouders).
/// Herhalende lokale melding; standaard aan, uit te zetten bij Meer.
@MainActor
enum WishDayReminder {
    static let enabledKey = "wishDayReminderEnabled"
    static let identifier = "miso.wishday"
    static let askedKey = "notificationsAsked"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// iOS-weekdag (1 = zondag … 7 = zaterdag) uit de serverweekdag (0 = maandag … 6 = zondag).
    nonisolated static func iosWeekday(fromServer day: Int) -> Int { (day + 1) % 7 + 1 }

    nonisolated static func message(isKid: Bool, dayName: String) -> (title: String, body: String) {
        isKid
            ? ("Het is boodschappendag! 🛒", "Geef vóór vanavond door wat je wilt eten of wat er mee moet met de boodschappen.")
            : ("Vandaag bestellen", "Bekijk de wensen van het gezin en zet de boodschappen voor volgende week klaar.")
    }

    /// Plan (of vervang) de wekelijkse melding. Zonder toestemming of uitgezet: weghalen.
    static func schedule(orderDay: Int, dayName: String, isKid: Bool) async {
        let center = UNUserNotificationCenter.current()
        guard isEnabled else { cancel(); return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let text = message(isKid: isKid, dayName: dayName)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.userInfo = ["tab": "plannen"]
        var when = DateComponents()
        when.weekday = iosWeekday(fromServer: orderDay)
        when.hour = 12
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Eén keer toestemming vragen zodra iemand gekozen heeft wie hij is (de melding is de bedoeling van de app).
    static func askOnce() async {
        let d = UserDefaults.standard
        guard !d.bool(forKey: askedKey) else { return }
        d.set(true, forKey: askedKey)
        if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }
}

/// Tik op een melding: open het juiste tabblad. Ook tonen als de app open staat.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    static let openTab = Notification.Name("MisoOpenTab")

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let tab = response.notification.request.content.userInfo["tab"] as? String ?? ""
        await MainActor.run { NotificationCenter.default.post(name: Self.openTab, object: tab) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
