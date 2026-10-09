import Foundation
import Testing
@testable import AHRecepten

struct RecipeDraftTests {
    private func recipe() throws -> RecipeDetail {
        let json = """
        {"id": 5, "name": "Soep", "servings": "4 personen", "total_time": "30 min", "image_url": "",
         "gf_mode": "none", "gf_note": "", "description": "Lekker", "source_url": "",
         "instructions": ["Snijd", "Kook"],
         "ingredients": [
           {"index": 0, "text": "2 uien", "skip": false, "gluten": false, "gf_search": "", "product": "Ui"},
           {"index": 1, "text": "1 l bouillon", "skip": false, "gluten": false, "gf_search": "", "product": null}]}
        """
        return try API.decoder.decode(RecipeDetail.self, from: Data(json.utf8))
    }

    @Test func unchangedDraftHasEmptyPatch() throws {
        let r = try recipe()
        #expect(RecipeDraft(recipe: r).patch(against: r).isEmpty)
    }

    @Test func onlyChangedFieldsAreSent() throws {
        let r = try recipe()
        var draft = RecipeDraft(recipe: r)
        draft.name = "  Uiensoep "
        draft.totalTime = "45 min"
        let patch = draft.patch(against: r)
        #expect(patch == RecipePatchBody(name: "Uiensoep", totalTime: "45 min"))

        let data = try JSONEncoder().encode(patch)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.sorted() == ["name", "total_time"])
    }

    @Test func linesAreTrimmedEmptyLinesDroppedAndOrderCounts() throws {
        let r = try recipe()
        var draft = RecipeDraft(recipe: r)
        draft.ingredients.append(EditableLine("   "))
        #expect(draft.patch(against: r).isEmpty) // alleen een lege regel erbij: niets veranderd

        draft.ingredients.swapAt(0, 1)
        #expect(draft.patch(against: r).ingredients == ["1 l bouillon", "2 uien"])

        draft.steps.append(EditableLine(" Serveer "))
        draft.steps.remove(at: 0)
        #expect(draft.patch(against: r).instructions == ["Kook", "Serveer"])
    }

    @Test func emptyNameCannotBeSaved() throws {
        var draft = RecipeDraft(recipe: try recipe())
        draft.name = "   "
        #expect(!draft.canSave)
    }
}
