import Foundation
import Testing
@testable import AHRecepten

/// `GET /api/plan/list-status`: staan de boodschappen klaar?
struct ListStatusTests {
    static let json = #"""
    {"ok": true, "connected": true, "week": "2026-10-12", "checked_at": "2026-10-11T17:45:00",
     "entries": [
      {"entry_id": 1, "date": "2026-10-12", "recipe_id": 5, "name": "Lasagne", "total": 7, "present": 3,
       "missing": ["gehakt", "lasagnebladen", "ricotta", "basilicum"], "status": "todo"},
      {"entry_id": 2, "date": "2026-10-13", "recipe_id": 6, "name": "AH verspakket 'Thaise' curry", "total": 4,
       "present": 4, "missing": [], "status": "ok"},
      {"entry_id": 3, "date": "2026-10-14", "recipe_id": 7, "name": "Nasi", "total": 5, "present": 5, "status": "ok"}
     ], "todo_count": 1}
    """#

    @Test func decodesAndSummarises() throws {
        let s = try API.decoder.decode(ListStatus.self, from: Data(Self.json.utf8))
        #expect(s.showsCard(hasPlanned: true))
        #expect(s.todoCount == 1)
        #expect(s.summary == "2 van 3 gerechten staan klaar op je AH-lijstje of in je bestelling")
        #expect(s.todoEntries.map(\.todoLine) == ["Lasagne · 4 van 7 producten mist"])
        #expect(s.entry(for: 2)?.badge == "Boodschappen ✓")
        #expect(s.entry(for: 1)?.badge == "Nog op lijstje zetten")
        #expect(s.entries(on: "2026-10-13").first?.todoLine == "Thaise curry · 0 van 4 producten mist")
        #expect(s.isChecked)
        #expect(s.checkedText.hasPrefix("Laatst gecontroleerd: "))
    }

    @Test func allReady() {
        let s = ListStatus(entries: [ListStatusEntry(entryId: 1, date: "d", name: "A", total: 2, present: 2, isTodo: false),
                                     ListStatusEntry(entryId: 2, date: "d", name: "B", total: 2, present: 2, isTodo: false)],
                           checkedAt: "2026-10-11T10:00:00")
        #expect(s.summary == "Alle 2 gerechten staan klaar op je AH-lijstje of in je bestelling ✓")
    }

    @Test func alreadyOrderedOrNotConnectedHidesCard() throws {
        let ordered = try API.decoder.decode(ListStatus.self, from: Data(
            #"{"ok": true, "connected": true, "week": "2026-10-05", "entries": [], "todo_count": 0, "already_ordered": true}"#.utf8))
        #expect(ordered.alreadyOrdered)
        #expect(!ordered.showsCard(hasPlanned: true))
        let notConnected = ListStatus(connected: false, entries: [], checkedAt: nil)
        #expect(!notConnected.showsCard(hasPlanned: true))
    }

    @Test func neverCheckedAsksToCheck() {
        let s = ListStatus(week: "2026-10-12", entries: [], checkedAt: nil)
        #expect(s.showsCard(hasPlanned: true))
        #expect(!s.showsCard(hasPlanned: false))
        #expect(s.checkedText == "Nog niet gecontroleerd of de boodschappen op je AH-lijstje staan.")
    }
}
