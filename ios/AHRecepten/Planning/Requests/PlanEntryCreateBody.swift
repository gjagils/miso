import Foundation

/// Body voor `POST /api/plan/entries`.
struct PlanEntryCreateBody: Encodable, Equatable {
    var date: String
    var kind: String
    var recipeId: Int?
    /// nil = huishoudgrootte.
    var persons: Int?
    var text: String?
    var extras: [String]?
    var cookDouble: CookDouble?
    var freezerItemId: Int?

    enum CodingKeys: String, CodingKey {
        case date, kind, persons, text, extras
        case recipeId = "recipe_id"
        case cookDouble = "cook_double"
        case freezerItemId = "freezer_item_id"
    }

    static func recipe(_ recipeId: Int, date: String, persons: Int?, cookDouble: CookDouble?) -> Self {
        PlanEntryCreateBody(date: date, kind: "recipe", recipeId: recipeId, persons: persons, cookDouble: cookDouble)
    }

    static func stock(date: String, text: String, extras: [String], freezerItemId: Int?) -> Self {
        PlanEntryCreateBody(date: date, kind: "stock", text: text, extras: extras, freezerItemId: freezerItemId)
    }
}
