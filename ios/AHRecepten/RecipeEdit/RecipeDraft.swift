import Foundation

/// Bewerkbare kopie van een recept. `patch(against:)` geeft alleen wat echt veranderd is.
struct RecipeDraft: Equatable {
    var name: String
    var servings: String
    var totalTime: String
    var description: String
    var steps: [EditableLine]
    var ingredients: [EditableLine]

    init(recipe: RecipeDetail) {
        name = recipe.name
        servings = recipe.servings
        totalTime = recipe.totalTime
        description = recipe.description
        steps = recipe.instructions.map { EditableLine($0) }
        ingredients = recipe.ingredients.map { EditableLine($0.text) }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { !trimmedName.isEmpty }

    /// Lege regels tellen niet mee.
    static func cleaned(_ lines: [EditableLine]) -> [String] {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func cleaned(_ texts: [String]) -> [String] {
        texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func patch(against original: RecipeDetail) -> RecipePatchBody {
        func changed(_ value: String, _ old: String) -> String? {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return v == old.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : v
        }
        var body = RecipePatchBody()
        body.name = changed(name, original.name)
        body.servings = changed(servings, original.servings)
        body.totalTime = changed(totalTime, original.totalTime)
        body.description = changed(description, original.description)
        let newSteps = Self.cleaned(steps)
        if newSteps != Self.cleaned(original.instructions) { body.instructions = newSteps }
        let newIngredients = Self.cleaned(ingredients)
        if newIngredients != Self.cleaned(original.ingredients.map(\.text)) { body.ingredients = newIngredients }
        return body
    }
}
