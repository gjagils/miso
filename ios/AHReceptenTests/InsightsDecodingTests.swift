import Foundation
import Testing
@testable import AHRecepten

struct InsightsDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func recipeCostSummary() throws {
        let c = try decode(RecipeCost.self, #"""
        {"ok": true, "recipe_id": 1, "total": 6.0, "bonus_saving": 0.3, "persons": 4, "per_person": 1.5,
         "known_count": 3, "complete": true, "unknown": [], "lines": []}
        """#)
        #expect(c.isUsable && c.complete)
        #expect(c.summary.hasPrefix("Ongeveer ") && c.summary.contains("voor 4") && c.summary.contains("p.p.")
                && c.summary.contains("bonusvoordeel") && !c.summary.contains("geen prijs"))
        let none = try decode(RecipeCost.self, #"{"ok": true, "total": 0, "known_count": 0, "persons": 4}"#)
        #expect(!none.isUsable && none.perPerson == nil)
        let partial = try decode(RecipeCost.self, #"{"total": 2.5, "known_count": 1, "persons": 4, "complete": false}"#)
        #expect(partial.summary.contains("niet alles heeft een prijs"))
    }

    @Test func weekCostSummary() throws {
        let c = try decode(WeekCost.self, #"""
        {"ok": true, "total": 54.2, "bonus_saving": 3.0, "per_meal": 2.1, "meals": 20, "known_count": 12,
         "unknown": ["Rijst", "Ui"], "unmatched_count": 0}
        """#)
        #expect(c.isUsable && c.unknown.count == 2)
        #expect(c.summary.contains("per bord") && c.summary.contains("bonusvoordeel") && c.summary.contains("2 producten zonder prijs"))
        let empty = try decode(WeekCost.self, #"{"ok": true, "total": 0, "per_meal": null, "known_count": 0}"#)
        #expect(!empty.isUsable && empty.perMeal == nil)
    }

    @Test func spendWithDetail() throws {
        let s = try decode(SpendResponse.self, #"""
        {"ok": true, "weeks": [{"week": "2026-10-05", "total": 40.5, "discount": 2.0, "trips": 2, "unknown": 0},
                               {"week": "2026-10-12", "total": 0.0, "discount": 0.0, "trips": 0, "unknown": 1}],
         "average_week": 40.5, "household_size": 4, "average_per_person_day": 1.45, "trips_total": 2, "since": "2026-07-20",
         "detail": {"week": "2026-10-05", "trips": [{"id": 1, "source": "bestelling", "date": "2026-10-05", "total": 38.0, "discount": 2.0, "lines": 9}],
                    "top": [{"product_id": 10, "name": "Melk", "quantity": 2.0, "amount": 2.4, "bonus": true}],
                    "categories": [{"category": "Zuivel", "amount": 12.0}]}}
        """#)
        #expect(s.weeks.count == 2 && s.weeks[0].trips == 2 && s.averageWeek == 40.5 && s.householdSize == 4)
        #expect(s.detail?.top.first?.bonus == true && s.detail?.categories.first?.category == "Zuivel")
        #expect(s.detail?.trips.first?.total == 38.0)
        let bare = try decode(SpendResponse.self, #"{"ok": true, "weeks": [], "average_week": null, "trips_total": 0}"#)
        #expect(bare.averageWeek == nil && bare.detail == nil && bare.tripsTotal == 0)
    }

    @Test func replenishItems() throws {
        let r = try decode(ReplenishResponse.self, #"""
        {"ok": true, "due": [{"product_id": 10, "name": "Melk", "status": "op", "interval_days": 7, "last_bought": "2026-10-06",
                              "due_on": "2026-10-13", "days_left": 0, "avg_quantity": 1.6, "times": 4},
                             {"product_id": 11, "name": "WC-papier", "status": "binnenkort", "interval_days": 35,
                              "last_bought": "2026-09-13", "days_left": 5, "avg_quantity": 1.0}]}
        """#)
        #expect(r.due.count == 2)
        #expect(r.due[0].isOverdue && r.due[0].quantity == 2 && r.due[0].whenText == "waarschijnlijk op")
        #expect(!r.due[1].isOverdue && r.due[1].whenText == "over 5 dagen op" && r.due[1].quantity == 1)
    }

    @Test func extrasBodyEncoding() throws {
        let data = try JSONEncoder().encode(ExtrasBody(products: [ExtrasProduct(productId: 10, name: "Melk", quantity: 2)]))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["list_ids"] as? [Any])?.isEmpty == true)
        let products = try #require(json["products"] as? [[String: Any]])
        #expect(products[0]["product_id"] as? Int == 10 && products[0]["quantity"] as? Int == 2)
        let snooze = try JSONEncoder().encode(SnoozeBody(productId: 10, days: 14))
        #expect(String(data: snooze, encoding: .utf8)?.contains("\"product_id\":10") == true)
    }

    @Test func proposalOptionWithBonus() throws {
        let o = try decode(ProposalOption.self, #"""
        {"recipe_id": 3, "name": "Rijst met garnalen", "image_url": "", "total_time": "25 min", "favorite": false,
         "bonus_saving": 2.0, "wished": true}
        """#)
        #expect(o.bonusSaving == 2.0 && o.wished)
        let old = try decode(ProposalOption.self, #"{"recipe_id": 3, "name": "Pasta"}"#)
        #expect(old.bonusSaving == 0 && !old.wished)
    }

    @Test func euroFormatting() {
        #expect(Euro.format(12.5).contains("12,50"))
        #expect(Euro.saving(2.8).hasPrefix("−") && Euro.saving(2.8).contains("2,80"))
    }
}

struct BudgetAndPantryTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func weekCostWithBudget() throws {
        let c = try decode(WeekCost.self, #"""
        {"ok": true, "total": 60.0, "known_count": 3, "unknown": [], "budget": 120, "budget_pct": 50, "actual": 90.0, "actual_pct": 75}
        """#)
        #expect(c.budget == 120 && c.budgetPct == 50 && c.actual == 90.0 && !c.overBudget)
        #expect(c.budgetText?.contains("geschat 50%") == true && c.budgetText?.contains("werkelijk") == true)
        let over = try decode(WeekCost.self, #"{"total": 150.0, "known_count": 2, "budget": 100, "budget_pct": 150, "actual": null}"#)
        #expect(over.overBudget && over.budgetText?.contains("werkelijk") == false)
        let none = try decode(WeekCost.self, #"{"total": 10.0, "known_count": 2, "budget": null, "budget_pct": null}"#)
        #expect(none.budgetText == nil && !none.overBudget)
    }

    @Test func settingsWithBudget() throws {
        let s = try decode(PlanSettings.self, #"{"ok": true, "household_size": 4, "order_weekday": 6, "order_weekday_name": "zondag", "week_budget": 150}"#)
        #expect(s.weekBudget == 150)
        let old = try decode(PlanSettings.self, #"{"household_size": 4, "order_weekday": 6}"#)
        #expect(old.weekBudget == 0)
        let body = try JSONEncoder().encode(PlanSettingsPatchBody(weekBudget: 120))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["week_budget"] as? Int == 120 && json["household_size"] == nil)
    }

    @Test func pantryFlagAndOutBody() throws {
        let r = try decode(ReplenishResponse.self, #"""
        {"due": [{"product_id": 7, "name": "AH Olijfolie", "status": "op", "interval_days": 35, "last_bought": "2026-08-01", "days_left": -3, "basis": true}]}
        """#)
        #expect(r.due[0].basis)
        let old = try decode(ReplenishItem.self, #"{"product_id": 8, "name": "Melk"}"#)
        #expect(!old.basis)
        let body = try JSONEncoder().encode(OutBody(productId: 7, name: "Olijfolie", quantity: 1))
        #expect(String(data: body, encoding: .utf8)?.contains("\"product_id\":7") == true)
    }
}

struct CheaperDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func cheaperResponse() throws {
        let r = try decode(CheaperResponse.self, #"""
        {"ok": true, "recipe_id": 1, "total_saving": 1.5, "suggestions": [
          {"index": 0, "text": "500 g kipfilet", "manual": false, "saving": 1.5,
           "current": {"id": 1, "name": "A-merk kipfilet", "unit_size": "500 g", "price": "6.00", "cost": 6.0, "packs": 1},
           "alternative": {"id": 2, "name": "AH Kipfilet", "unit_size": "500 g", "price": "4.50", "image_url": "https://x/y.jpg",
                           "brand": "AH", "category": "Vlees", "available": true, "organic": false, "unit_price": "", "nix18": false,
                           "cost": 4.5, "packs": 1}}]}
        """#)
        #expect(r.ok && r.suggestions.count == 1 && r.totalSaving == 1.5)
        let s = r.suggestions[0]
        #expect(s.index == 0 && s.saving == 1.5 && !s.manual)
        #expect(s.alternative.product.id == 2 && s.alternative.product.name == "AH Kipfilet" && s.alternative.cost == 4.5)
        #expect(s.current.product.unitSize == "500 g" && s.current.cost == 6.0 && s.current.packs == 1)
        // Het gekozen product gaat met snake_case-sleutels terug naar de server
        let body = IngredientUpdateBody.choose(s.alternative.product, text: s.text)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let product = try #require(json["product"] as? [String: Any])
        #expect(product["id"] as? Int == 2 && product["unit_size"] as? String == "500 g" && product["image_url"] as? String == "https://x/y.jpg")
        #expect(json["text"] as? String == "500 g kipfilet")
    }

    @Test func emptyAndFailedResponses() throws {
        let empty = try decode(CheaperResponse.self, #"{"ok": true, "suggestions": [], "total_saving": 0}"#)
        #expect(empty.ok && empty.suggestions.isEmpty && empty.totalSaving == 0)
        let failed = try decode(CheaperResponse.self, #"{"ok": false, "error": "Recept niet gevonden."}"#)
        #expect(!failed.ok && failed.error == "Recept niet gevonden." && failed.suggestions.isEmpty)
    }
}

struct BonusDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func bonusRecipes() throws {
        let r = try decode(BonusRecipesResponse.self, #"""
        {"ok": true, "period": {"start": "2026-10-19", "end": "2026-10-25"}, "bonus_count": 40,
         "recipes": [{"id": 3, "name": "Rijst met garnalen", "image_url": "/image/3", "servings": "4 personen", "total_time": "25 min",
                      "bonus_count": 2, "linked_count": 4, "coverage": 0.5, "saving": 2.8, "items": []},
                     {"id": 4, "name": "Soep", "bonus_count": 1, "saving": null}]}
        """#)
        #expect(r.ok && r.recipes.count == 2 && r.recipes[0].bonusCount == 2)
        #expect(r.recipes[0].meta.contains("voordeel") && r.recipes[1].meta.isEmpty)
        #expect(r.isNextWeek(today: "2026-10-13") && r.title(today: "2026-10-13") == "Volgende week in de bonus")
        #expect(!r.isNextWeek(today: "2026-10-20") && r.title(today: "2026-10-20") == "Deze week in de bonus")
        #expect(r.subtitle(today: "2026-10-13").hasPrefix("Aanbiedingen van") && r.subtitle(today: "2026-10-20").hasPrefix("Aanbiedingen t/m"))
        let item = PickItem.bonus(r.recipes[0])
        #expect(item.key == "own:3" && item.chip == "2 in de bonus" && item.kind == .own)
        let failed = try decode(BonusRecipesResponse.self, #"{"ok": false, "error": "AH niet gekoppeld."}"#)
        #expect(!failed.ok && failed.recipes.isEmpty)
    }
}
