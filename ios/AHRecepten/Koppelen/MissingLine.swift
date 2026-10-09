import Foundation

/// Eén open ingrediëntregel in een recept (`GET /api/missing`). Gaat ongewijzigd terug naar
/// `POST /api/missing/assign`, zodat de server controleert of de regel nog dezelfde is.
struct MissingLine: Codable, Hashable, Sendable {
    let recipeId: Int
    let recipe: String
    let index: Int
    let text: String

    private enum CodingKeys: String, CodingKey { case recipeId, recipe, index, text }
    private enum EncodingKeys: String, CodingKey { case recipe, index, text, recipeId = "recipe_id" }

    init(recipeId: Int, recipe: String, index: Int, text: String) {
        self.recipeId = recipeId
        self.recipe = recipe
        self.index = index
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipeId = c.lenientInt(.recipeId) ?? 0
        recipe = c.lenient(String.self, .recipe) ?? ""
        index = c.lenientInt(.index) ?? 0
        text = c.lenient(String.self, .text) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: EncodingKeys.self)
        try c.encode(recipeId, forKey: .recipeId)
        try c.encode(recipe, forKey: .recipe)
        try c.encode(index, forKey: .index)
        try c.encode(text, forKey: .text)
    }
}
