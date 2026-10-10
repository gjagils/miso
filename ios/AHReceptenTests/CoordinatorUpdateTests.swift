import Foundation
import Testing
@testable import AHRecepten

/// Nieuwe server-velden en regels uit de UX-ronde (main, 10 okt): 5 doordeweekse dagen, overgeslagen dagen,
/// maaltijdpakket-label, "te vroeg" bij opruimen met ongedaan maken, gekookt na de helft van de stappen.
struct CoordinatorUpdateTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func nextWeekStatusCountsWeekdays() throws {
        let s = try decode(NextWeekStatus.self, #"""
        {"ok": true, "weekdays_planned": 3, "ready": false, "days_until_order": 2, "week": "2026-10-19",
         "planned_days": 4, "total_days": 7, "prominent": true, "message": "Volgende week: 3 van 5"}
        """#)
        #expect(s.progressPlanned == 3 && s.progressTotal == 5 && !s.isComplete)
        let ready = try decode(NextWeekStatus.self, #"{"weekdays_planned": 5, "ready": true, "planned_days": 5}"#)
        #expect(ready.isComplete) // weekend leeg is prima
        // Oudere server: zoals vroeger 7 dagen.
        let old = try decode(NextWeekStatus.self, #"{"planned_days": 4, "total_days": 7}"#)
        #expect(old.progressPlanned == 4 && old.progressTotal == 7 && !old.isComplete)
    }

    @Test func reminderUsesWeekdays() {
        let status = NextWeekStatus(daysUntilOrder: 2, week: "2026-10-19", plannedDays: 4, weekdaysPlanned: 3, ready: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10))!
        guard case .schedule(_, let body) = OrderReminderPlanner.decide(enabled: true, status: status, now: now,
                                                                        calendar: calendar) else {
            Issue.record("verwacht een herinnering")
            return
        }
        #expect(body.hasSuffix("(3/5)"))
    }

    @Test func applySkippedAndPackOption() throws {
        let a = try decode(PlanApplyResponse.self, #"{"ok": true, "added": 3, "skipped": ["2026-10-14"]}"#)
        #expect(a.added == 3 && a.skipped == ["2026-10-14"])
        let old = try decode(PlanApplyResponse.self, #"{"ok": true, "added": 1}"#)
        #expect(old.skipped.isEmpty)
        let o = try decode(ProposalOption.self, #"{"recipe_id": 4, "name": "Shakshuka", "pack": true}"#)
        #expect(o.pack && !o.allerhande)
    }

    @Test func reviewTooEarly() throws {
        let r = try decode(RecipesReviewResponse.self,
                           #"{"too_early": true, "total_plans": 12, "min_plans": 30, "recipes": []}"#)
        #expect(r.tooEarly && r.totalPlans == 12 && r.minPlans == 30)
        let old = try decode(RecipesReviewResponse.self, #"{"total_plans": 40, "recipes": []}"#)
        #expect(!old.tooEarly && old.minPlans == 30)
    }

    @Test func undoBodiesReverseTheAction() throws {
        func json(_ body: RecipeFlagsBody) throws -> [String: Bool] {
            try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Bool])
        }
        #expect(try json(ReviewAction.keep.body) == ["reviewed": true])
        #expect(try json(ReviewAction.keep.undoBody) == ["reviewed": false])
        #expect(try json(ReviewAction.byHeart.undoBody) == ["by_heart": false, "reviewed": false])
        #expect(try json(ReviewAction.archive.undoBody) == ["archived": false])
        #expect(ReviewAction.archive.done("Quiche") == "Quiche opgeruimd.")
    }

    @Test(arguments: [(0, 4, false), (1, 4, false), (2, 4, true), (2, 5, false), (3, 5, true), (1, 1, true), (0, 0, false)])
    func cookedAfterHalfTheSteps(done: Int, steps: Int, expected: Bool) {
        #expect(CookProgress.isHalfway(done: done, steps: steps) == expected)
    }

    @Test func feedbackRating() throws {
        let f = try decode(RecipeFeedbackResponse.self, #"{"ok": true, "thumbs_up": 1, "thumbs_down": 0, "rating": "down"}"#)
        #expect(f.rating == .down)
    }

    @Test func chipGroups() {
        #expect(WishChip.main.map(\.label) == ["Rijst", "Pasta", "Aardappel", "Wraps", "Uit de vriezer", "Geen idee"])
        #expect(WishChip.more.map(\.label) == ["Noedels", "Vis", "Vega", "Kip", "Snel klaar", "Overslaan"])
        #expect(Set(WishChip.main + WishChip.more) == Set(WishChip.allCases))
        #expect(WishChip.vis.isMore && !WishChip.rijst.isMore)
    }

    @Test func takenDayCanBeCleared() throws {
        let entries = try API.decoder.decode(PlanEntriesResponse.self, from: Data(PlanFixtures.entries.utf8)).entries
        let week = PlannenDay.week(monday: "2026-10-12", today: "2026-10-13", entries: entries)
        #expect(week[0].entryIDs == [12] && !week[0].canClear)   // voorbij
        #expect(week[1].entryIDs == [13] && week[1].canClear)
        #expect(week[3].entryIDs.isEmpty && !week[3].canClear)   // open
    }
}
