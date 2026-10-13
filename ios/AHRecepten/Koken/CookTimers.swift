import Foundation
import Observation
import UserNotifications

/// Een lopende timer.
struct RunningTimer: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let end: Date
    /// Is er al gezegd dat hij klaar is (geluid/trilling)?
    var rang = false

    func remaining(at now: Date) -> Int { max(0, Int(end.timeIntervalSince(now).rounded(.up))) }
    func isDone(at now: Date) -> Bool { end <= now }
}

enum TimerFormat {
    /// 1200 -> "20:00", 3725 -> "1:02:05".
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = s % 3600 / 60, x = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
    }
}

/// De timers van één kookbeurt. Een lokale melding laat het weten als de app op de achtergrond staat.
@MainActor
@Observable
final class CookTimers {
    private(set) var running: [RunningTimer] = []
    /// Voor tests vervangbaar: plant/annuleert de melding. Standaard de echte meldingen van iOS.
    var scheduler: TimerNotifying = SystemTimerNotifier()

    func start(_ timer: StepTimer, recipeName: String, now: Date = .now) {
        let running = RunningTimer(id: UUID(), label: timer.label, end: now.addingTimeInterval(TimeInterval(timer.seconds)))
        self.running.append(running)
        scheduler.schedule(id: running.id, title: "Timer klaar", body: "\(timer.label) · \(recipeName)", after: TimeInterval(timer.seconds))
    }

    func stop(_ id: UUID) {
        running.removeAll { $0.id == id }
        scheduler.cancel(id: id)
    }

    func stopAll() {
        for timer in running { scheduler.cancel(id: timer.id) }
        running = []
    }

    /// Timers die net klaar zijn en nog niet gemeld; markeert ze als gemeld. De weergave speelt er geluid bij af.
    func newlyDone(at now: Date) -> [RunningTimer] {
        var fresh: [RunningTimer] = []
        for index in running.indices where !running[index].rang && running[index].isDone(at: now) {
            running[index].rang = true
            fresh.append(running[index])
        }
        return fresh
    }
}

protocol TimerNotifying: Sendable {
    func schedule(id: UUID, title: String, body: String, after seconds: TimeInterval)
    func cancel(id: UUID)
}

struct SystemTimerNotifier: TimerNotifying {
    func schedule(id: UUID, title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        // Zonder toestemming gebeurt er niets; de timer in de app werkt dan gewoon door.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "miso.timer.\(id)", content: content, trigger: trigger))
    }

    func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["miso.timer.\(id)"])
    }
}
