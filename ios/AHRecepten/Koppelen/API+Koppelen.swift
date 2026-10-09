import Foundation

// Ingrediënten koppelen aan AH-producten en Ontbrekend (zelfde endpoints als de web-versie).
// Er wordt nooit iets besteld.
extension API {
    func searchProducts(_ query: String) async throws -> [AHProduct] {
        let result: AHProductSearchResponse = try await get("api/ah/search", query: [URLQueryItem(name: "q", value: query)])
        if result.products.isEmpty, let error = result.error, !error.isEmpty {
            throw APIError(message: "Zoeken bij AH lukte niet. Probeer het zo nog eens.")
        }
        return result.products
    }

    /// Eén ingrediënt koppelen, uitvinken of het aantal wijzigen. Gooit een `APIError` met `isConflict`
    /// als het recept intussen is gewijzigd.
    func updateIngredient(recipeID: Int, index: Int, _ body: IngredientUpdateBody) async throws -> Ingredient {
        let result: IngredientUpdateResponse = try await post("api/recipes/\(recipeID)/ingredients/\(index)", json: body)
        guard result.ok, let ingredient = result.ingredient else {
            throw APIError(message: result.error ?? "Opslaan is niet gelukt.")
        }
        return ingredient
    }

    func missing() async throws -> MissingResponse {
        try await get("api/missing")
    }

    /// `product: nil` = niet nodig.
    func assignMissing(lines: [MissingLine], product: AHProduct?) async throws -> MissingAssignResponse {
        try await post("api/missing/assign", json: MissingAssignBody(lines: lines, product: product))
    }
}
