import Foundation

/// Eén voorstel van `POST /api/week/suggest`: recept voor een lege dag.
struct MenuSuggestion: Decodable, Identifiable, Hashable, Sendable {
    let date: String
    let recipeId: Int
    let name: String
    let profiel: HealthProfile?

    var id: String { "\(date)/\(recipeId)" }
}
