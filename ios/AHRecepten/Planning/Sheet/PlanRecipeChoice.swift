import Foundation

/// Recept dat ingepland wordt: een eigen recept of een Allerhande-recept (wordt bij opslaan eerst toegevoegd).
struct PlanRecipeChoice: Identifiable, Hashable {
    enum Source: Hashable { case own, allerhande }

    let source: Source
    /// Recept-id op de server (eigen) of Allerhande-id.
    let recipeID: Int
    let name: String
    let imageUrl: String
    let meta: String

    var id: String { "\(source == .own ? "own" : "ah"):\(recipeID)" }

    static func own(_ r: RecipeSummary) -> PlanRecipeChoice {
        PlanRecipeChoice(source: .own, recipeID: r.id, name: r.name, imageUrl: r.imageUrl,
                         meta: ["jouw recept", r.servings].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    static func own(_ r: RecipeDetail) -> PlanRecipeChoice {
        PlanRecipeChoice(source: .own, recipeID: r.id, name: r.name, imageUrl: r.imageUrl,
                         meta: r.servings.isEmpty ? "" : "recept voor \(r.servings)")
    }

    static func allerhande(_ h: AHRecipeHit) -> PlanRecipeChoice {
        PlanRecipeChoice(source: .allerhande, recipeID: h.id, name: h.title, imageUrl: h.imageUrl ?? "",
                         meta: ["Allerhande", h.time ?? "", h.servings].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}
