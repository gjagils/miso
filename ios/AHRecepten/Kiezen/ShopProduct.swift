import Foundation

/// Samengevoegd AH-product op de boodschappenlijst.
struct ShopProduct: Identifiable, Equatable {
    let id: Int
    let name: String
    let size: String
    let image: String
    var qty: Int
    var recipes: [String]
}
