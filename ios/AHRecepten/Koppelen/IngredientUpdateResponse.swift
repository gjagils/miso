import Foundation

/// Antwoord op `POST /api/recipes/{id}/ingredients/{index}`.
struct IngredientUpdateResponse: Decodable {
    let ok: Bool
    let ingredient: Ingredient?
    let error: String?
}
