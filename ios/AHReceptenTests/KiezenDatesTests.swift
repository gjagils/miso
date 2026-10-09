import Foundation
import Testing
@testable import AHRecepten

struct KiezenDatesTests {
    @Test func parseAndFormatRoundTrip() throws {
        let date = try #require(KiezenDates.parse("2025-10-06"))
        #expect(KiezenDates.iso(date) == "2025-10-06")
    }

    @Test func parseRejectsGarbage() {
        #expect(KiezenDates.parse("") == nil)
        #expect(KiezenDates.parse("2025-10") == nil)
        #expect(KiezenDates.parse("vandaag") == nil)
    }

    @Test(arguments: [
        ("2025-10-06", 7, "2025-10-13"),
        ("2025-10-06", -7, "2025-09-29"),
        ("2025-12-29", 7, "2026-01-05"),
        ("2024-02-28", 1, "2024-02-29"), // schrikkeljaar
        ("2025-03-29", 2, "2025-03-31"), // zomertijd
    ])
    func addDays(start: String, days: Int, expected: String) {
        #expect(KiezenDates.add(start, days) == expected)
    }

    @Test func addKeepsInvalidInput() {
        #expect(KiezenDates.add("onzin", 7) == "onzin")
    }

    @Test(arguments: [
        ("2025-10-06", "Maandag 6 okt"),
        ("2025-10-12", "Zondag 12 okt"),
        ("2026-01-01", "Donderdag 1 jan"),
        ("2025-05-17", "Zaterdag 17 mei"),
    ])
    func label(date: String, expected: String) {
        #expect(KiezenDates.label(date) == expected)
    }

    @Test func shortLabel() {
        #expect(KiezenDates.short("2025-10-06") == "6 okt")
        #expect(KiezenDates.label("geen datum") == "geen datum")
    }

    @Test func todayIsISO() {
        let today = KiezenDates.today
        #expect(KiezenDates.parse(today) != nil)
        #expect(today.count == 10)
    }
}
