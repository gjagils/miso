import Foundation
import Testing
@testable import AHRecepten

struct DayChipBuilderTests {
    private func entry(_ id: Int, _ date: String, _ title: String) throws -> PlanItem {
        let json = #"{"entry_id": \#(id), "date": "\#(date)", "kind": "recipe", "title": "\#(title)", "recipe_id": 1}"#
        return try API.decoder.decode(PlanItem.self, from: Data(json.utf8))
    }

    @Test func sevenDaysWithWeekdaysAndOccupied() throws {
        let entries = [try entry(1, "2026-10-12", "Lasagne"), try entry(2, "2026-10-12", "Salade"),
                       try entry(3, "2026-10-14", "Soep"), try entry(4, "2026-10-30", "Buiten het venster")]
        let chips = DayChipBuilder.chips(start: "2026-10-12", today: "2026-10-09", entries: entries)
        #expect(chips.map(\.date) == ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15",
                                      "2026-10-16", "2026-10-17", "2026-10-18"])
        #expect(chips.map(\.weekdayShort) == ["ma", "di", "wo", "do", "vr", "za", "zo"])
        #expect(chips.map(\.dayNumber) == [12, 13, 14, 15, 16, 17, 18])
        #expect(chips.map(\.isOccupied) == [true, false, true, false, false, false, false])
        #expect(chips[0].occupied == ["Lasagne", "Salade"])
        #expect(chips[0].accessibilityLabel == "Maandag 12 okt, al gepland: Lasagne, Salade")
        #expect(chips.allSatisfy { !$0.isPast && !$0.isToday })
    }

    @Test func pastAndTodayAcrossMonthEnd() {
        let chips = DayChipBuilder.chips(start: "2026-09-28", today: "2026-10-01", entries: [])
        #expect(chips.map(\.isPast) == [true, true, true, false, false, false, false])
        #expect(chips.map(\.isToday) == [false, false, false, true, false, false, false])
        #expect(chips.map(\.dayNumber) == [28, 29, 30, 1, 2, 3, 4])
    }

    @Test func movedEntryDoesNotBlockItsOwnDay() throws {
        let entries = [try entry(12, "2026-10-12", "Lasagne")]
        let chips = DayChipBuilder.chips(start: "2026-10-12", today: "2026-10-09", entries: entries, ignoring: 12)
        #expect(chips.allSatisfy { !$0.isOccupied })
    }

    @Test func info() throws {
        let chips = DayChipBuilder.chips(start: "2026-10-12", today: "2026-10-09",
                                         entries: [try entry(1, "2026-10-12", "Lasagne")])
        #expect(DayChipBuilder.info(for: nil, chips: chips) == "Kies een dag.")
        #expect(DayChipBuilder.info(for: "2026-10-12", chips: chips) == "Maandag 12 okt: er staat al Lasagne")
        #expect(DayChipBuilder.info(for: "2026-10-13", chips: chips) == "Dinsdag 13 okt")
    }

    @Test func initialWindow() {
        // Weekmenu "+": venster = de week, dag = die dag.
        #expect(DayChipBuilder.initialWindow(start: "2026-10-12", date: "2026-10-14", today: "2026-10-09")
                == ("2026-10-12", "2026-10-14"))
        // Dag buiten het venster: venster schuift naar die dag.
        #expect(DayChipBuilder.initialWindow(start: "2026-10-05", date: "2026-10-14", today: "2026-10-09")
                == ("2026-10-14", "2026-10-14"))
        // Geen dag, huidige week: vandaag.
        #expect(DayChipBuilder.initialWindow(start: "2026-10-05", date: nil, today: "2026-10-09")
                == ("2026-10-05", "2026-10-09"))
        // Geen start: vanaf vandaag.
        #expect(DayChipBuilder.initialWindow(start: nil, date: nil, today: "2026-10-09") == ("2026-10-09", "2026-10-09"))
        // Kies-modus zonder dag: geen standaarddag.
        #expect(DayChipBuilder.initialWindow(start: "2026-10-12", date: nil, today: "2026-10-09", chooseDefault: false)
                == ("2026-10-12", nil))
    }

    @Test func firstFreeDay() throws {
        let entries = [try entry(1, "2026-10-09", "Vandaag"), try entry(2, "2026-10-10", "Morgen")]
        #expect(DayChipBuilder.firstFreeDay(week: "2026-10-05", today: "2026-10-09", entries: entries) == "2026-10-11")
        #expect(DayChipBuilder.firstFreeDay(week: "2026-10-05", today: "2026-10-12", entries: []) == nil)
    }

    @Test func weekdayHelpers() {
        #expect(KiezenDates.weekdayIndex("2026-10-12") == 0)
        #expect(KiezenDates.weekdayIndex("2026-10-18") == 6)
        #expect(KiezenDates.weekdayIndex("onzin") == nil)
        #expect(KiezenDates.weekdayName("2026-10-14") == "Woensdag")
    }
}
