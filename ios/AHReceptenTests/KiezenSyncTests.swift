import Foundation
import Testing
@testable import AHRecepten

struct KiezenSyncTests {
    private func assignment(_ id: Int, day: String, already: String? = nil) -> Assignment {
        Assignment(recipeId: id, name: "R\(id)", imageUrl: "", day: day, already: already, persons: 4)
    }

    @Test func onlyRecipesWithoutDayAndNotAlreadyPlannedAreLoose() {
        let list = [
            assignment(1, day: "2026-10-12"),
            assignment(2, day: ""),
            assignment(3, day: "", already: "2026-10-13"),
            assignment(4, day: ""),
        ]
        #expect(Assignment.unplannedIDs(list) == [2, 4])
    }

    @Test func cartFillResultDecodes() throws {
        let json = #"{"ok": true, "items_added": 5, "unmatched": ["saffraan"]}"#
        let r = try API.decoder.decode(CartFillResult.self, from: Data(json.utf8))
        #expect(r.ok && r.itemsAdded == 5 && r.unmatched == ["saffraan"])
    }
}
