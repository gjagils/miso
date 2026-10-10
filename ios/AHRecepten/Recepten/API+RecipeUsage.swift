import Foundation

// Favorieten, "uit mijn hoofd", opruimen en "Lekker?" (backend/app/api/json_api.py).
extension API {
    func recipes(query: String = "", filter: RecipeFilter) async throws -> [RecipeSummary] {
        var items: [URLQueryItem] = []
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if !filter.serverValue.isEmpty { items.append(URLQueryItem(name: "filter", value: filter.serverValue)) }
        let result: RecipesResponse = try await get("api/recipes", query: items)
        return filter.apply(result.recipes)
    }

    func setRecipeFlags(_ id: Int, _ body: RecipeFlagsBody) async throws -> RecipeFlagsResponse {
        try await patch("api/recipes/\(id)/flags", json: body)
    }

    func sendFeedback(_ id: Int, rating: TasteRating) async throws -> RecipeFeedbackResponse {
        try await post("api/recipes/\(id)/feedback", json: RecipeFeedbackBody(rating: rating))
    }

    /// Kookmodus geopend: telt als gekookt (de server telt één keer per dag).
    func markCooked(_ id: Int) async throws -> RecipeCookedResponse {
        try await post("api/recipes/\(id)/cooked", json: EmptyBody())
    }

    func recipesReview() async throws -> RecipesReviewResponse {
        try await get("api/recipes-review")
    }
}
