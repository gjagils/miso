import Foundation

/// Ingrediëntregel zonder AH-product (of uit de basisvoorraad), met het recept waar hij bij hoort.
struct ShopLine: Identifiable {
    let id = UUID()
    let text: String
    let recipeId: Int
    let recipeName: String
}
