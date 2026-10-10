import Foundation

/// Gekozen voorstel voor één dag: een (eigen of Allerhande-)recept, of "iets uit de vriezer".
struct PlanApplyChoice: Encodable, Equatable, Sendable {
    let date: String
    /// "recipe" of "vriezer".
    let kind: String
    let recipeId: Int?
    let ahRecipeId: Int?

    enum CodingKeys: String, CodingKey {
        case date, kind
        case recipeId = "recipe_id"
        case ahRecipeId = "ah_recipe_id"
    }

    static func recipe(_ option: ProposalOption, date: String) -> Self {
        PlanApplyChoice(date: date, kind: "recipe", recipeId: option.recipeId, ahRecipeId: option.ahRecipeId)
    }

    static func freezer(date: String) -> Self {
        PlanApplyChoice(date: date, kind: "vriezer", recipeId: nil, ahRecipeId: nil)
    }
}
