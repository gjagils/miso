import Foundation
import Testing
@testable import AHRecepten

struct OrderReminderPlannerTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    private func status(daysUntilOrder: Int, planned: Int, total: Int = 7) -> NextWeekStatus {
        NextWeekStatus(daysUntilOrder: daysUntilOrder, week: "2026-10-12", plannedDays: planned, totalDays: total)
    }

    @Test func schedulesEveningBeforeOrderDay() throws {
        // Vrijdag 9 okt 10:00, besteldag zondag 11 okt -> zaterdag 10 okt 19:00.
        let decision = OrderReminderPlanner.decide(enabled: true, status: status(daysUntilOrder: 2, planned: 4),
                                                   now: try date(9, 10), calendar: calendar)
        #expect(decision == .schedule(fireDate: try date(10, 19),
                                      body: "Het weekmenu voor volgende week is nog niet compleet (4/7)"))
    }

    @Test func eveningBeforeLaterToday() throws {
        // Zaterdag 18:30, besteldag morgen -> vandaag 19:00.
        let decision = OrderReminderPlanner.decide(enabled: true, status: status(daysUntilOrder: 1, planned: 0),
                                                   now: try date(10, 18, 30), calendar: calendar)
        #expect(decision == .schedule(fireDate: try date(10, 19),
                                      body: "Het weekmenu voor volgende week is nog niet compleet (0/7)"))
    }

    @Test func cancelsWhenMomentPassed() throws {
        // Zaterdag 19:30: de herinnering van vanavond is al voorbij.
        #expect(OrderReminderPlanner.decide(enabled: true, status: status(daysUntilOrder: 1, planned: 3),
                                            now: try date(10, 19, 30), calendar: calendar) == .cancel)
        // Besteldag is vandaag.
        #expect(OrderReminderPlanner.decide(enabled: true, status: status(daysUntilOrder: 0, planned: 3),
                                            now: try date(11, 9), calendar: calendar) == .cancel)
    }

    @Test func cancelsWhenCompleteOrDisabledOrUnknown() throws {
        let now = try date(9, 10)
        #expect(OrderReminderPlanner.decide(enabled: true, status: status(daysUntilOrder: 2, planned: 7),
                                            now: now, calendar: calendar) == .cancel)
        #expect(OrderReminderPlanner.decide(enabled: false, status: status(daysUntilOrder: 2, planned: 4),
                                            now: now, calendar: calendar) == .cancel)
        #expect(OrderReminderPlanner.decide(enabled: true, status: nil, now: now, calendar: calendar) == .cancel)
    }

    @Test func farAwayOrderDay() throws {
        // Maandag 5 okt, besteldag zondag 11 okt (6 dagen) -> zaterdag 10 okt 19:00.
        let decision = OrderReminderPlanner.decide(enabled: true, status: status(daysUntilOrder: 6, planned: 1),
                                                   now: try date(5, 8), calendar: calendar)
        guard case .schedule(let fire, _) = decision else {
            Issue.record("verwacht een herinnering")
            return
        }
        #expect(fire == (try date(10, 19)))
    }
}
