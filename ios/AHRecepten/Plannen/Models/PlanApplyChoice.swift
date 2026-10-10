import Foundation

/// Gekozen voorstel voor één dag: een (eigen of Allerhande-)recept, of "iets uit de vriezer".
struct PlanApplyChoice: Encodable, Equatable, Sendable {
    let date: String
    /// "recipe" of "vriezer".
    let kind: String
    let recipeId: Int?
    let ahRecipeId: Int?
    /// "Wijzig": wat er op die dag stond, gaat pas weg als dit erin komt.
    var replace = false

    enum CodingKeys: String, CodingKey {
        case date, kind, replace
        case recipeId = "recipe_id"
        case ahRecipeId = "ah_recipe_id"
    }

    static func recipe(_ option: ProposalOption, date: String, replace: Bool = false) -> Self {
        PlanApplyChoice(date: date, kind: "recipe", recipeId: option.recipeId, ahRecipeId: option.ahRecipeId,
                        replace: replace)
    }

    static func freezer(date: String, replace: Bool = false) -> Self {
        PlanApplyChoice(date: date, kind: "vriezer", recipeId: nil, ahRecipeId: nil, replace: replace)
    }

    /// Eén recept op één dag (wens van het gezin: "Zet op deze dag").
    static func recipe(id: Int, date: String) -> Self {
        PlanApplyChoice(date: date, kind: "recipe", recipeId: id, ahRecipeId: nil)
    }
}
