import Foundation
import Testing
@testable import AHRecepten

struct PlanModelsDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func recipeEntry() throws {
        let e = try decode(PlanItem.self, PlanFixtures.recipeEntry)
        #expect(e.entryId == 12)
        #expect(e.id == "entry/12")
        #expect(e.kind == .recipe)
        #expect(e.persons == 6)
        #expect(e.personsIsDefault == false)
        #expect(e.groceryPersons == 12)
        #expect(e.recipeId == 1)
        #expect(e.recipe?.totalTime == "45 min")
        #expect(e.cookDouble == .tomorrow)
        #expect(e.leftoverEntryIds == [13])
        #expect(e.isEditable && e.hasPersons)
    }

    @Test func leftoverEntry() throws {
        let e = try decode(PlanItem.self, PlanFixtures.leftoverEntry)
        #expect(e.kind == .leftover)
        #expect(e.title == "Rest van Lasagne bolognese")
        #expect(e.sourceEntryId == 12)
        #expect(e.cookDouble == nil)
        #expect(e.hasPersons)
    }

    @Test func stockEntryWithExtras() throws {
        let e = try decode(PlanItem.self, PlanFixtures.stockEntry)
        #expect(e.kind == .stock)
        #expect(e.recipeId == nil && e.recipe == nil)
        #expect(e.text == "Pastasaus uit de vriezer")
        #expect(e.extras.map(\.text) == ["spaghetti", "iets onvindbaars"])
        #expect(e.extras[0].productId == 159760)
        #expect(e.extras[1].product == nil)
        #expect(!e.hasPersons)
    }

    @Test func entryWithOnlyADateAndUnknownKind() throws {
        let e = try decode(PlanItem.self, #"{"date": "2026-10-12", "kind": "picknick", "extras": ["brood"], "cook_double": "overmorgen"}"#)
        #expect(e.kind == .other)
        #expect(e.entryId == nil && !e.isEditable)
        #expect(e.extras.map(\.text) == ["brood"])
        #expect(e.cookDouble == nil)
        #expect(e.persons == 0)
    }

    @Test func entriesResponse() throws {
        let r = try decode(PlanEntriesResponse.self, PlanFixtures.entries)
        #expect(r.start == "2026-10-12")
        #expect(r.householdSize == 4)
        #expect(r.entries.map(\.kind) == [.recipe, .leftover, .stock])
    }

    @Test func createPatchDeleteResponses() throws {
        let created = try decode(PlanCreateResponse.self, PlanFixtures.createResponse)
        #expect(created.ok)
        #expect(created.entries.count == 2)
        #expect(created.freezerItem == nil)
        #expect(created.status?.newCount == 1)
        #expect(created.status?.onList == 3)
        #expect(created.summary == "Lasagne bolognese staat op maandag 12 okt (voor 6), de rest op dinsdag 13 okt.")

        let patched = try decode(PlanUpdateResponse.self, PlanFixtures.patchResponse)
        #expect(patched.entry?.entryId == 12)
        #expect(patched.weeks == ["2026-10-12"])

        let deleted = try decode(PlanDeleteResponse.self, PlanFixtures.deleteResponse)
        #expect(deleted.deleted == [12, 13])
    }

    @Test func weekWithEntries() throws {
        let w = try decode(WeekResponse.self, PlanFixtures.week)
        #expect(w.householdSize == 4)
        #expect(w.status.newCount == 6)
        #expect(w.days[0].recipes[0].entryId == 12)
        let items = w.days[0].planItems(householdSize: 4)
        #expect(items.map(\.entryId) == [12])
        #expect(w.days[1].planItems(householdSize: 4).first?.kind == .stock)
    }

    @Test func legacyWeekFallsBackToRecipes() throws {
        let w = try decode(WeekResponse.self, PlanFixtures.legacyWeek)
        #expect(w.householdSize == nil)
        #expect(w.status.missingCount == nil)
        #expect(w.status.newCount == 1) // valt terug op missing.count
        let items = w.days[0].planItems(householdSize: 5)
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)).count == 2) // twee keer hetzelfde recept: toch unieke ids
        #expect(items.allSatisfy { $0.kind == .recipe && $0.persons == 5 && !$0.isEditable })
    }

    @Test func nextWeekStatus() throws {
        let s = try decode(NextWeekStatus.self, PlanFixtures.nextWeekStatus)
        #expect(s.orderDay == 6 && s.orderDayName == "zondag")
        #expect(s.daysUntilOrder == 2)
        #expect(s.week == "2026-10-12")
        #expect(s.plannedDays == 4 && s.totalDays == 7 && !s.isComplete)
        #expect(s.missingDates.count == 3)
        #expect(s.prominent)
        #expect(s.listStatus?.missingCount == 6)
    }

    @Test func nextWeekStatusMinimal() throws {
        let s = try decode(NextWeekStatus.self, #"{"ok": true, "days_until_order": 1, "planned_days": 7}"#)
        #expect(s.totalDays == 7 && s.isComplete)
        #expect(s.prominent) // afgeleid: <= 2 dagen tot de besteldag
        #expect(s.orderDayName == "zondag")
        #expect(s.listStatus == nil)
    }

    @Test func settings() throws {
        let s = try decode(PlanSettings.self, PlanFixtures.settings)
        #expect(s == PlanSettings(householdSize: 4, orderWeekday: 6, orderWeekdayName: "zondag"))
        let fallback = try decode(PlanSettings.self, #"{"ok": true, "order_weekday": 0}"#)
        #expect(fallback.householdSize == 4)
        #expect(fallback.orderWeekdayName == "maandag")
    }

    @Test func freezer() throws {
        let list = try decode(FreezerListResponse.self, PlanFixtures.freezerList)
        #expect(list.items.map(\.name) == ["Pasta pesto", "Soep"])
        #expect(list.items[0].fromRecipeId == 2)
        #expect(list.items[1].portions == 2) // getal als tekst
        #expect(list.items[1].addedOn == nil)
        let deleted = try decode(FreezerItemResponse.self, PlanFixtures.freezerDeleted)
        #expect(deleted.deleted && deleted.item == nil)
    }

    @Test func healthAndSuggest() throws {
        let h = try decode(WeekHealth.self, PlanFixtures.health)
        #expect(h.dagen == 5 && h.restjes == 1)
        #expect(h.profilesByEntry.keys.sorted() == [12])
        #expect(h.profilesByEntry[12]?.chips == ["vlees", "pasta", "~700 kcal"])
        #expect(h.summary.hasPrefix("5 avonden (1 restje)"))

        let s = try decode(SuggestResponse.self, PlanFixtures.suggest)
        #expect(s.voorstel.map(\.recipeId) == [7])
        #expect(s.voorstel[0].profiel?.eiwit == "vis")
        #expect(s.zonderProfiel == 0)
    }

    // MARK: Request bodies

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func createBodies() throws {
        let recipe = try json(PlanEntryCreateBody.recipe(1, date: "2026-10-12", persons: 6, cookDouble: .tomorrow))
        #expect(recipe["kind"] as? String == "recipe")
        #expect(recipe["recipe_id"] as? Int == 1)
        #expect(recipe["persons"] as? Int == 6)
        #expect(recipe["cook_double"] as? String == "tomorrow")

        let household = try json(PlanEntryCreateBody.recipe(1, date: "2026-10-12", persons: nil, cookDouble: nil))
        #expect(household["persons"] == nil) // weglaten = huishoudgrootte

        let stock = try json(PlanEntryCreateBody.stock(date: "2026-10-14", text: "Pastasaus uit de vriezer",
                                                       extras: ["spaghetti"], freezerItemId: nil))
        #expect(stock["kind"] as? String == "stock")
        #expect(stock["extras"] as? [String] == ["spaghetti"])
        #expect(stock["recipe_id"] == nil)
    }

    @Test func patchBodySendsNullForHousehold() throws {
        let toHousehold = try JSONEncoder().encode(PlanEntryPatchBody(persons: .from(4, household: 4)))
        #expect(String(decoding: toHousehold, as: UTF8.self) == #"{"persons":null}"#)
        let move = try json(PlanEntryPatchBody(date: "2026-10-15"))
        #expect(move["date"] as? String == "2026-10-15")
        #expect(move.keys.contains("persons") == false)
        let six = try json(PlanEntryPatchBody(persons: .from(6, household: 4)))
        #expect(six["persons"] as? Int == 6)
    }
}
