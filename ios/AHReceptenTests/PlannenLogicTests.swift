import Foundation
import Testing
@testable import AHRecepten

/// Wensen verzamelen, standaardweek en de zin-invoer (zelfde regels als /plannen).
struct PlannenLogicTests {
    // Week van maandag 12 oktober 2026.
    private let monday = "2026-10-12"

    private func days(today: String, taken: [String: String] = [:]) -> [PlannenDay] {
        (0..<7).map { offset in
            let date = KiezenDates.add(monday, offset)
            return PlannenDay(date: date, taken: taken[date] ?? "", isPast: date < today)
        }
    }

    // MARK: Standaardweek

    @Test(arguments: [
        ("2026-10-12", [String](), "2026-10-12"),                     // maandag, alles open: deze week
        ("2026-10-14", [String](), "2026-10-12"),                     // woensdag, nog open: deze week
        ("2026-10-15", [String](), "2026-10-19"),                     // donderdag: volgende week
        ("2026-10-18", [String](), "2026-10-19"),                     // zondag: volgende week
        ("2026-10-13", ["2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"], "2026-10-19"), // di, rest vol
        ("2026-10-13", ["2026-10-12"], "2026-10-12"),                 // maandag gepland, di-vr open
    ])
    func defaultWeek(today: String, taken: [String], expected: String) {
        #expect(PlannenLogic.defaultWeek(today: today, takenDates: Set(taken)) == expected)
    }

    @Test func mondayOf() {
        #expect(PlannenLogic.monday(of: "2026-10-18") == "2026-10-12")
        #expect(PlannenLogic.monday(of: "2026-10-12") == "2026-10-12")
        #expect(PlannenLogic.monday(of: "2026-01-01") == "2025-12-29")
    }

    // MARK: Wensen

    @Test func wishInputChipAndTextExcludeEachOther() {
        var wish = WishInput()
        #expect(wish.isEmpty && wish.value == nil)
        wish.toggle(.rijst)
        #expect(wish.value == "rijst")
        wish.setText("lasagne")
        #expect(wish.chip == nil && wish.value == "lasagne")
        wish.toggle(.vis)
        #expect(wish.chip == .vis && wish.text.isEmpty)
        wish.toggle(.vis)
        #expect(wish.isEmpty)
        #expect(WishInput(text: "   ").value == nil)
        #expect(WishInput(text: " nasi goreng ").value == "nasi goreng")
    }

    @Test func serverValueBecomesChipOrText() {
        #expect(WishInput(serverValue: "vriezer").chip == .vriezer)
        #expect(WishInput(serverValue: "Wraps").chip == .wraps)
        #expect(WishInput(serverValue: "lasagne").text == "lasagne")
    }

    @Test func collectSkipsTakenAndPastDays() {
        let week = days(today: "2026-10-13", taken: ["2026-10-14": "Pannenkoeken"])
        let wishes: [String: WishInput] = [
            "2026-10-12": WishInput(chip: .pasta),         // voorbij
            "2026-10-13": WishInput(chip: .rijst),
            "2026-10-14": WishInput(chip: .vis),           // bezet
            "2026-10-15": WishInput(text: "lasagne"),
            "2026-10-16": WishInput(text: "  "),           // leeg
            "2026-10-17": WishInput(chip: .overslaan),
        ]
        #expect(PlannenLogic.collect(wishes, days: week) == [
            "2026-10-13": "rijst", "2026-10-15": "lasagne", "2026-10-17": "overslaan",
        ])
    }

    @Test func mergeSentenceOnlyFillsOpenDays() {
        let week = days(today: "2026-10-12", taken: ["2026-10-14": "Restjes"])
        var wishes: [String: WishInput] = ["2026-10-13": WishInput(chip: .pasta)]
        let filled = PlannenLogic.merge(
            ["2026-10-12": "rijst", "2026-10-13": "wraps", "2026-10-14": "vis", "2026-10-15": "lasagne",
             "2026-10-20": "kip", "2026-10-16": ""],
            into: &wishes, days: week)
        #expect(filled == ["2026-10-12", "2026-10-13", "2026-10-15"])
        #expect(wishes["2026-10-12"]?.chip == .rijst)
        #expect(wishes["2026-10-13"]?.chip == .wraps) // zin overschrijft
        #expect(wishes["2026-10-14"] == nil)
        #expect(wishes["2026-10-15"]?.text == "lasagne")
        #expect(wishes["2026-10-20"] == nil)
    }

    @Test func fillEmptyWeekdaysWithNoIdea() {
        let week = days(today: "2026-10-13", taken: ["2026-10-15": "Soep"])
        var wishes: [String: WishInput] = ["2026-10-14": WishInput(chip: .vis)]
        PlannenLogic.fillEmptyWeekdays(&wishes, days: week)
        #expect(wishes["2026-10-12"] == nil)            // voorbij
        #expect(wishes["2026-10-13"]?.chip == .vrij)
        #expect(wishes["2026-10-14"]?.chip == .vis)     // blijft
        #expect(wishes["2026-10-15"] == nil)            // bezet
        #expect(wishes["2026-10-16"]?.chip == .vrij)
        #expect(wishes["2026-10-17"] == nil)            // weekend niet
    }

    @Test func plannenDayWeekUsesEntries() throws {
        let entries = try API.decoder.decode(PlanEntriesResponse.self, from: Data(PlanFixtures.entries.utf8)).entries
        let week = PlannenDay.week(monday: monday, today: "2026-10-13", entries: entries)
        #expect(week.count == 7)
        #expect(week[0].taken == "Lasagne bolognese" && week[0].isPast && !week[0].isOpen)
        #expect(week[1].taken == "Rest van Lasagne bolognese")
        #expect(week[3].isOpen && !week[3].isWeekend)
        #expect(week[5].isWeekend && week[6].isWeekend)
    }

    @Test(arguments: [
        ("25 min", 25), ("1 uur", 60), ("1 uur 15 min", 75), ("90 minuten", 90), ("", nil), ("snel", nil),
    ] as [(String, Int?)])
    func minutes(text: String, expected: Int?) {
        #expect(PlannenLogic.minutes(text) == expected)
    }

    @Test func chipsMatchServerOrder() {
        #expect(WishChip.allCases.map(\.rawValue) == ["rijst", "pasta", "aardappel", "wraps", "noedels", "vis",
                                                       "vega", "kip", "snel", "vriezer", "vrij", "overslaan"])
        #expect(WishChip.vrij.label == "Geen idee" && WishChip.snel.label == "Snel klaar")
    }
}
