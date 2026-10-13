import Foundation
import Testing
@testable import AHRecepten

private final class FakeNotifier: TimerNotifying, @unchecked Sendable {
    var scheduled: [(id: UUID, body: String, after: TimeInterval)] = []
    var cancelled: [UUID] = []
    func schedule(id: UUID, title: String, body: String, after seconds: TimeInterval) { scheduled.append((id, body, seconds)) }
    func cancel(id: UUID) { cancelled.append(id) }
}

@MainActor
struct CookTimersTests {
    @Test func startStopAndNotifications() {
        let timers = CookTimers()
        let fake = FakeNotifier()
        timers.scheduler = fake
        let now = Date(timeIntervalSince1970: 1_000_000)
        timers.start(StepTimer(seconds: 1200, label: "20 min"), recipeName: "Soep", now: now)
        timers.start(StepTimer(seconds: 90, label: "90 sec"), recipeName: "Soep", now: now)
        #expect(timers.running.count == 2 && fake.scheduled.count == 2)
        #expect(fake.scheduled[0].body == "20 min · Soep" && fake.scheduled[0].after == 1200)
        let first = timers.running[0]
        #expect(first.remaining(at: now) == 1200 && first.remaining(at: now.addingTimeInterval(1199.4)) == 1)
        #expect(first.remaining(at: now.addingTimeInterval(5000)) == 0)
        timers.stop(first.id)
        #expect(timers.running.count == 1 && fake.cancelled == [first.id])
        timers.stopAll()
        #expect(timers.running.isEmpty && fake.cancelled.count == 2)
    }

    @Test func announcesEachTimerOnlyOnce() {
        let timers = CookTimers()
        timers.scheduler = FakeNotifier()
        let now = Date(timeIntervalSince1970: 1_000_000)
        timers.start(StepTimer(seconds: 60, label: "1 min"), recipeName: "Soep", now: now)
        timers.start(StepTimer(seconds: 300, label: "5 min"), recipeName: "Soep", now: now)
        #expect(timers.newlyDone(at: now.addingTimeInterval(30)).isEmpty)
        #expect(timers.newlyDone(at: now.addingTimeInterval(61)).map(\.label) == ["1 min"])
        #expect(timers.newlyDone(at: now.addingTimeInterval(62)).isEmpty)  // al gemeld
        #expect(timers.newlyDone(at: now.addingTimeInterval(400)).map(\.label) == ["5 min"])
    }

    @Test func clockFormatting() {
        #expect(TimerFormat.clock(1200) == "20:00" && TimerFormat.clock(65) == "1:05" && TimerFormat.clock(0) == "0:00")
        #expect(TimerFormat.clock(3725) == "1:02:05" && TimerFormat.clock(-5) == "0:00")
    }

    @Test func stepTimersDecodeFromRecipe() throws {
        let json = #"""
        {"id": 1, "name": "Soep", "servings": "4", "total_time": "30", "image_url": "", "gf_mode": "none", "gf_note": "",
         "description": "", "source_url": "", "instructions": ["Snijd.", "Laat 20 minuten sudderen."],
         "step_timers": [[], [{"seconds": 1200, "label": "20 min"}]], "ingredients": []}
        """#
        let r = try API.decoder.decode(RecipeDetail.self, from: Data(json.utf8))
        #expect(r.stepTimers?.count == 2 && r.stepTimers?[0].isEmpty == true && r.stepTimers?[1].first?.seconds == 1200)
        let old = try API.decoder.decode(RecipeDetail.self, from: Data(#"""
        {"id": 2, "name": "Oud", "servings": "4", "total_time": "", "image_url": "", "gf_mode": "none", "gf_note": "",
         "description": "", "source_url": "", "instructions": [], "ingredients": []}
        """#.utf8))
        #expect(old.stepTimers == nil)
    }
}
