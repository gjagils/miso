import Foundation

/// `{recipe_ids, persons: {"<id>": n}}` voor `POST /api/list-link` en `POST /api/basket/fill`.
struct RecipePersonsBody: Encodable {
    let recipeIds: [Int]
    let persons: [String: Int]

    enum CodingKeys: String, CodingKey {
        case recipeIds = "recipe_ids"
        case persons
    }
}
