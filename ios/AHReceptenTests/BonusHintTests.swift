import Foundation
import Testing
@testable import AHRecepten

struct BonusHintTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        c.firstWeekday = 2
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = cal.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    private let hint = BonusHint(count: 2, saving: 3, names: ["A", "B"], message: "2 recepten zitten volgende week in de bonus.")

    @Test func statusDecodesHint() throws {
        let s = try API.decoder.decode(NextWeekStatus.self, from: Data(#"""
        {"days_until_order": 3, "week": "2026-10-19", "planned_days": 2,
         "bonus_hint": {"count": 2, "saving": 3.0, "names": ["A", "B"], "message": "2 recepten ..."}}
        """#.utf8))
        #expect(s.bonusHint?.count == 2 && s.bonusHint?.isUseful == true)
        let old = try API.decoder.decode(NextWeekStatus.self, from: Data(#"{"days_until_order": 3, "week": "2026-10-19"}"#.utf8))
        #expect(old.bonusHint == nil)
        #expect(BonusHint().isUseful == false)
    }

    @Test func schedulesNextFridayAtFive() {
        // woensdag 14 okt: vrijdag 16 okt 17:00, volgende week begint maandag 19 okt
        let d = BonusHintPlanner.decide(enabled: true, hint: hint, nextWeek: "2026-10-19",
                                        now: date("2026-10-14T10:00:00+02:00"), calendar: cal)
        #expect(d == .schedule(fireDate: date("2026-10-16T17:00:00+02:00"), body: hint.message))
    }

    @Test func fridayBeforeAndAfterFive() {
        let before = BonusHintPlanner.decide(enabled: true, hint: hint, nextWeek: "2026-10-19",
                                             now: date("2026-10-16T09:00:00+02:00"), calendar: cal)
        #expect(before == .schedule(fireDate: date("2026-10-16T17:00:00+02:00"), body: hint.message))
        let after = BonusHintPlanner.decide(enabled: true, hint: hint, nextWeek: "2026-10-19",
                                            now: date("2026-10-16T18:00:00+02:00"), calendar: cal)
        #expect(after == .cancel)
    }

    @Test func weekendWouldTalkAboutTheWrongWeek() {
        // zaterdag: "volgende week" is al ma 19 okt; de eerstvolgende vrijdag ligt na die maandag
        let d = BonusHintPlanner.decide(enabled: true, hint: hint, nextWeek: "2026-10-19",
                                        now: date("2026-10-17T10:00:00+02:00"), calendar: cal)
        #expect(d == .cancel)
    }

    @Test func offOrNothingToSayCancels() {
        let now = date("2026-10-14T10:00:00+02:00")
        #expect(BonusHintPlanner.decide(enabled: false, hint: hint, nextWeek: "2026-10-19", now: now, calendar: cal) == .cancel)
        #expect(BonusHintPlanner.decide(enabled: true, hint: BonusHint(), nextWeek: "2026-10-19", now: now, calendar: cal) == .cancel)
        #expect(BonusHintPlanner.decide(enabled: true, hint: nil, nextWeek: "2026-10-19", now: now, calendar: cal) == .cancel)
        #expect(BonusHintPlanner.decide(enabled: true, hint: hint, nextWeek: "onzin", now: now, calendar: cal) == .cancel)
    }
}
