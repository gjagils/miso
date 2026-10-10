import Foundation
import Testing
@testable import AHRecepten

/// Wisselen van voorstellen en wat er naar `POST /api/plan/apply` gaat.
struct ProposalSelectionTests {
    private func selection() throws -> ProposalSelection {
        let r = try API.decoder.decode(ProposeResponse.self, from: Data(PlannenDecodingTests.propose.utf8))
        return ProposalSelection(days: r.days)
    }

    @Test func defaultsToFirstOption() throws {
        let s = try selection()
        let rice = s.days[0]
        #expect(s.chosen(for: rice)?.recipeId == 7)
        #expect(s.alternatives(for: rice).map(\.index) == [1, 2])
        #expect(s.swapped.isEmpty)
        #expect(s.choices == [
            PlanApplyChoice(date: "2026-10-12", kind: "recipe", recipeId: 7, ahRecipeId: nil),
            PlanApplyChoice(date: "2026-10-13", kind: "vriezer", recipeId: nil, ahRecipeId: nil),
        ])
        #expect(s.plannedCount == 2)
    }

    @Test func swappingTracksFirstProposal() throws {
        var s = try selection()
        let rice = s.days[0]
        s.choose(2, for: rice)
        #expect(s.chosen(for: rice)?.ahRecipeId == 1234)
        #expect(s.alternatives(for: rice).map(\.index) == [0, 1])
        #expect(s.swapped == [7])
        #expect(s.choices.first == PlanApplyChoice(date: "2026-10-12", kind: "recipe", recipeId: nil, ahRecipeId: 1234))
        // Terugwisselen naar Miso's keuze: geen weggewisseld signaal meer.
        s.choose(0, for: rice)
        #expect(s.swapped.isEmpty)
    }

    @Test func invalidIndexIsIgnored() throws {
        var s = try selection()
        s.choose(9, for: s.days[0])
        #expect(s.pick(for: s.days[0]) == 0)
    }

    @Test func allerhandeFirstProposalIsNotCountedAsSwapped() {
        let day = ProposalDay(date: "2026-10-12", kind: .recipe, options: [
            ProposalOption(ahRecipeId: 1, name: "AH", allerhande: true),
            ProposalOption(recipeId: 5, name: "Eigen"),
        ])
        var s = ProposalSelection(days: [day])
        s.choose(1, for: day)
        #expect(s.swapped.isEmpty)
        #expect(s.choices == [PlanApplyChoice(date: "2026-10-12", kind: "recipe", recipeId: 5, ahRecipeId: nil)])
    }

    @Test func applyBodyEncodesSnakeCase() throws {
        var s = try selection()
        s.choose(1, for: s.days[0])
        let body = PlanApplyBody(week: "2026-10-12", choices: s.choices, swapped: s.swapped)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(json["week"] as? String == "2026-10-12")
        #expect(json["swapped"] as? [Int] == [7])
        let choices = try #require(json["choices"] as? [[String: Any]])
        #expect(choices[0]["recipe_id"] as? Int == 8)
        #expect(choices[1]["kind"] as? String == "vriezer")
    }

    @Test func todaySuggestions() {
        func recipe(_ id: Int, _ time: String, favorite: Bool = false) -> RecipeSummary {
            let json = #"{"id": \#(id), "name": "R\#(id)", "servings": "", "total_time": "\#(time)", "image_url": "", "gf_mode": "none", "favorite": \#(favorite)}"#
            return try! API.decoder.decode(RecipeSummary.self, from: Data(json.utf8))
        }
        let fav = recipe(1, "20 min", favorite: true)
        let all = [fav, recipe(2, "1 uur"), recipe(3, "25 min"), recipe(4, "")]
        let s = TodaySuggestion.make(favorites: [fav], all: all, dayNumber: 3)
        #expect(s.map(\.id) == ["fav/1", "freezer", "quick/3"])
        // Zonder favorieten en snelle recepten blijft de vriezer over.
        #expect(TodaySuggestion.make(favorites: [], all: [recipe(2, "1 uur")], dayNumber: 0).map(\.id) == ["freezer"])
    }
}
