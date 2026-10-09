import Foundation

/// Ingrediënt dat in het koppel-blad openstaat.
struct IngredientSelection: Identifiable {
    /// Plek in `RecipeDetail.ingredients`.
    let position: Int
    let ingredient: Ingredient

    var id: Int { position }
    /// Index voor de server; oudere servers sturen geen index, dan is het de plek in de lijst.
    var serverIndex: Int { ingredient.index ?? position }
}
