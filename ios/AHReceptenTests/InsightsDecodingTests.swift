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
