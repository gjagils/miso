import Foundation
import Testing
@testable import AHRecepten

/// Decoderen van de nieuwe endpoints: plannen met wensen, favorieten/opruimen en "Lekker?".
struct PlannenDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    static let propose = #"""
    {"ok": true, "week": "2026-10-12", "days": [
      {"date": "2026-10-12", "wish": "iets met rijst", "chip": "rijst", "label": "Rijst", "kind": "recipe",
       "options": [
         {"recipe_id": 7, "name": "Nasi goreng", "image_url": "/image/7", "total_time": "30 min", "favorite": true},
         {"recipe_id": 8, "name": "Risotto", "image_url": "", "total_time": "45 min", "favorite": false},
         {"ah_recipe_id": 1234, "name": "Rijstbowl", "image_url": "https://x/y.jpg", "total_time": "20 min", "allerhande": true}
       ]},
      {"date": "2026-10-13", "wish": "vriezer", "chip": "vriezer", "label": "Uit de vriezer", "kind": "vriezer", "options": []},
      {"date": "2026-10-14", "wish": "lasagne", "chip": "lasagne", "label": "lasagne", "kind": "taken",
       "taken": "Pannenkoeken", "options": []},
      {"date": "2026-10-15", "wish": "xyz", "chip": "xyz", "label": "xyz", "kind": "none", "options": []},
      {"date": "2026-10-16", "wish": "overslaan", "chip": "overslaan", "label": "Overslaan", "kind": "overslaan", "options": []}
    ]}
    """#

    @Test func proposeResponse() throws {
        let r = try decode(ProposeResponse.self, Self.propose)
        #expect(r.ok && r.week == "2026-10-12")
        #expect(r.days.map(\.kind) == [.recipe, .vriezer, .taken, .none, .overslaan])
        let rice = r.days[0]
        #expect(rice.label == "Rijst" && rice.chip == "rijst")
        #expect(rice.options.count == 3)
        #expect(rice.options[0].recipeId == 7 && rice.options[0].favorite && !rice.options[0].allerhande)
        #expect(rice.options[2].ahRecipeId == 1234 && rice.options[2].recipeId == nil && rice.options[2].allerhande)
        #expect(rice.options[2].meta == "20 min · Allerhande")
        #expect(r.days[2].taken == "Pannenkoeken")
    }

    @Test func unknownKindAndEmptyRecipeDayBecomeNone() throws {
        let json = #"""
        {"ok": true, "week": "2026-10-12", "days": [
            {"date": "2026-10-12", "kind": "iets-nieuws", "options": []},
            {"date": "2026-10-13", "kind": "recipe", "options": []}]}
        """#
        let r = try decode(ProposeResponse.self, json)
        #expect(r.days.map(\.kind) == [.none, .none])
    }

    @Test func allerhandeOptionWithoutFlagIsStillAllerhande() throws {
        let o = try decode(ProposalOption.self, #"{"ah_recipe_id": "55", "name": "Wraps"}"#)
        #expect(o.ahRecipeId == 55 && o.allerhande && o.meta == "Allerhande")
    }

    @Test func wishesText() throws {
        let r = try decode(WishesTextResponse.self,
                           #"{"ok": true, "wishes": {"2026-10-12": "rijst", "2026-10-15": "lasagne"}}"#)
        #expect(r.ok && r.wishes["2026-10-15"] == "lasagne")
        let failed = try decode(WishesTextResponse.self, #"{"ok": false, "error": "Miso snapte de zin niet."}"#)
        #expect(!failed.ok && failed.wishes.isEmpty && failed.error == "Miso snapte de zin niet.")
    }

    @Test func applyResponse() throws {
        let r = try decode(PlanApplyResponse.self, #"{"ok": true, "added": 4, "status": "# + PlanFixtures.status + "}")
        #expect(r.ok && r.added == 4 && r.status?.newCount == 1)
    }

    @Test func recipeSummaryWithFlags() throws {
        let json = #"""
        {"recipes": [
          {"id": 1, "name": "Pakket", "servings": "2", "total_time": "", "image_url": "", "gf_mode": "none",
           "favorite": true, "by_heart": false, "archived": false, "collection": "maaltijdpakket"},
          {"id": 2, "name": "Oud", "servings": "", "total_time": "", "image_url": "", "gf_mode": "none"}
        ]}
        """#
        let r = try decode(RecipesResponse.self, json)
        #expect(r.recipes[0].isFavorite && r.recipes[0].isMealKit && !r.recipes[0].isByHeart)
        // Oudere server zonder de nieuwe velden.
        #expect(!r.recipes[1].isFavorite && !r.recipes[1].isMealKit)
        #expect(RecipeFilter.mealKits.apply(r.recipes).map(\.id) == [1])
        #expect(RecipeFilter.favorites.apply(r.recipes).count == 2) // server filtert al
    }

    @Test func recipeDetailUsage() throws {
        let json = #"""
        {"id": 3, "name": "Stamppot", "servings": "4", "total_time": "30 min", "image_url": "", "gf_mode": "none",
         "favorite": false, "by_heart": true, "archived": false, "collection": "",
         "description": "", "cooked_count": 3, "thumbs_up": 2, "thumbs_down": 0, "source_url": "", "gf_note": "",
         "instructions": ["Kook"], "ingredients": []}
        """#
        let r = try decode(RecipeDetail.self, json)
        #expect(r.isByHeart && !r.isFavorite && !r.isArchived && !r.isMealKit)
        #expect(RecipeFlagsBar.usageLine(cooked: r.cookedCount, up: r.thumbsUp, down: r.thumbsDown)
                == "3× gekookt · 👍 2 · 👎 0")
        #expect(RecipeFlagsBar.usageLine(cooked: nil, up: nil, down: nil) == "Nog niet gekookt met Miso")
    }

    @Test func reviewList() throws {
        let json = #"""
        {"total_plans": 40, "recipes": [
          {"id": 9, "name": "Quiche", "image_url": "", "reason": "Nog nooit gekozen", "planned": 0, "cooked": 0,
           "thumbs_up": 0, "thumbs_down": 0, "last_eaten": null, "age_days": 200, "by_heart": false},
          {"id": 10, "name": "Curry", "image_url": "", "reason": "Vaker 👎 dan 👍", "planned": 2, "cooked": 1,
           "thumbs_up": 1, "thumbs_down": 2, "last_eaten": "2026-03-03", "age_days": 300, "by_heart": true}
        ]}
        """#
        let r = try decode(RecipesReviewResponse.self, json)
        #expect(r.totalPlans == 40 && r.recipes.count == 2)
        #expect(r.recipes[0].lastEaten == nil)
        #expect(r.recipes[0].statsLine == "Nog nooit gekozen · 0× gepland · 0× gekookt")
        #expect(r.recipes[1].byHeart)
        #expect(r.recipes[1].statsLine == "Vaker 👎 dan 👍 · 2× gepland · 1× gekookt · 👍 1 👎 2 · laatst 3 mrt")
    }

    @Test func feedbackAndCooked() throws {
        let f = try decode(RecipeFeedbackResponse.self, #"{"ok": true, "thumbs_up": 3, "thumbs_down": 1}"#)
        #expect(f.thumbsUp == 3 && f.thumbsDown == 1)
        let c = try decode(RecipeCookedResponse.self, #"{"ok": true, "cooked": 5}"#)
        #expect(c.cooked == 5)
    }

    @Test func flagsBodyOnlySendsSetFields() throws {
        let data = try JSONEncoder().encode(RecipeFlagsBody.byHeartKeep)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(object == ["by_heart": true, "reviewed": true])
        let archive = try JSONEncoder().encode(RecipeFlagsBody.archive)
        #expect(String(decoding: archive, as: UTF8.self) == #"{"archived":true}"#)
    }
}
