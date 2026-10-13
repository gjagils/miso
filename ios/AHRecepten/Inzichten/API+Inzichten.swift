import Foundation

// Kosten, uitgaven en "waarschijnlijk op" (docs/plan-api.md). Alleen lezen, plus producten op het AH-lijstje zetten.
// Er wordt nooit iets besteld.
extension API {
    func recipeCost(_ id: Int) async throws -> RecipeCost {
        try await get("api/recipes/\(id)/cost")
    }

    func weekCost(_ week: String) async throws -> WeekCost {
        try await get("api/week/cost", query: [URLQueryItem(name: "week", value: week)])
    }

    func spend(weeks: Int = 12, detail: String? = nil) async throws -> SpendResponse {
        var query = [URLQueryItem(name: "weeks", value: String(weeks))]
        if let detail { query.append(URLQueryItem(name: "detail", value: detail)) }
        return try await get("api/spend", query: query)
    }

    func syncAHData() async throws -> InsightResult {
        try await post("api/ah/sync", form: [:])
    }

    func replenish(week: String) async throws -> [ReplenishItem] {
        let result: ReplenishResponse = try await get("api/replenish", query: [URLQueryItem(name: "week", value: week)])
        return result.due
    }

    func snooze(productID: Int, days: Int) async throws -> InsightResult {
        try await post("api/replenish/snooze", json: SnoozeBody(productId: productID, days: days))
    }

    /// Producten (zonder AH-lijsten) op het AH-lijstje zetten. AH-fouten komen terug als `ok: false`.
    func addToList(_ products: [ExtrasProduct]) async throws -> InsightResult {
        try await post("api/ah-extras/to-list", json: ExtrasBody(products: products))
    }

    /// "Dit is op" (tijdens het koken): op het AH-lijstje en de voorspelling even met rust laten. Bestelt niets.
    func markOut(productID: Int, name: String) async throws -> InsightResult {
        try await post("api/replenish/out", json: OutBody(productId: productID, name: name, quantity: 1))
    }

    /// Goedkopere AH-producten voor een recept (zoekt bij AH; kan even duren). Wijzigt niets.
    func cheaper(recipeID: Int) async throws -> CheaperResponse {
        try await post("api/recipes/\(recipeID)/cheaper", form: [:])
    }

    /// Eigen recepten met ingrediënten in de bonus van de periode waarin `week` valt (nil = deze week).
    func bonusRecipes(week: String?, limit: Int = 6) async throws -> BonusRecipesResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let week, !week.isEmpty { query.append(URLQueryItem(name: "week", value: week)) }
        return try await get("api/bonus/recipes", query: query)
    }
}
