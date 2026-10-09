import Foundation

// Recept bewerken en verwijderen.
extension API {
    /// Alleen de velden in `body` worden aangepast; geeft het hele recept terug.
    func updateRecipe(_ id: Int, _ body: RecipePatchBody) async throws -> RecipeDetail {
        try await patch("api/recipes/\(id)", json: body)
    }

    func deleteRecipe(_ id: Int) async throws {
        let _: OKResponse = try await delete("api/recipes/\(id)")
    }
}
