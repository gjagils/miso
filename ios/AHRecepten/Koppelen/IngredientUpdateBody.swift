import Foundation

/// Body voor `POST /api/recipes/{id}/ingredients/{index}`: koppelen, uitvinken of aantal wijzigen.
/// `text` is de huidige tekst van de regel; klopt die niet meer, dan geeft de server 409.
/// Velden die nil zijn, worden niet meegestuurd (een `"product": null` zou ontkoppelen).
struct IngredientUpdateBody: Encodable, Equatable, Sendable {
    let text: String
    var product: AHProduct?
    var skip: Bool?
    var quantity: Int?

    static func choose(_ product: AHProduct, text: String) -> IngredientUpdateBody {
        IngredientUpdateBody(text: text, product: product)
    }

    /// "Niet nodig" (true) of weer wel nodig (false).
    static func skip(_ skip: Bool, text: String) -> IngredientUpdateBody {
        IngredientUpdateBody(text: text, skip: skip)
    }

    static func quantity(_ quantity: Int, text: String) -> IngredientUpdateBody {
        IngredientUpdateBody(text: text, quantity: quantity)
    }
}
