import Foundation
import Testing
@testable import AHRecepten

struct CookWithTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func suggestionDecodesAndDescribes() throws {
        let r = try decode(CookWithResponse.self, #"""
        {"ok": true, "suggestions": [
          {"recipe_id": 7, "name": "Courgette met gehakt", "image_url": "", "total_time": "40 min", "servings": "4 personen",
           "covered": 2, "total": 3, "missing_count": 1,
           "matches": [{"ingredient": "500 g gehakt", "from": "Gehakt", "source": "vriezer"},
                       {"ingredient": "1 courgette", "from": "AH Biologisch Courgette", "source": "gekocht"}]}],
         "inventory": {"freezer": ["Gehakt"], "bought": []}}
        """#)
        let s = try #require(r.suggestions.first)
        #expect(s.id == 7 && s.covered == 2 && s.matches.first?.isFreezer == true)
        #expect(s.detail == "Nog 1 ingrediënt nodig · 40 min")
        #expect(s.haveText == "500 g gehakt (vriezer), 1 courgette (gekocht)")
    }

    @Test func detailVariantsAndMissingFields() throws {
        let all = CookWithSuggestion(recipeId: 1, name: "A", covered: 3, total: 3, missingCount: 0)
        #expect(all.detail == "Alles al in huis")
        let two = CookWithSuggestion(recipeId: 1, name: "A", totalTime: "20 min", covered: 2, total: 4, missingCount: 2)
        #expect(two.detail == "Nog 2 ingrediënten nodig · 20 min")
        let empty = try decode(CookWithResponse.self, #"{"ok": true}"#)
        #expect(empty.suggestions.isEmpty)
        // een voorstel zonder recept-id is onbruikbaar, maar mag de lijst niet laten mislukken
        let lenient = try decode(CookWithResponse.self, #"{"suggestions": [{"name": "kapot"}]}"#)
        #expect(lenient.suggestions.isEmpty)
    }
}
