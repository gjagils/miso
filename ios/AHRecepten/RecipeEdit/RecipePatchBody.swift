import Foundation

/// Body voor `PATCH /api/recipes/{id}`. Velden die nil zijn, worden niet meegestuurd en blijven gelijk.
struct RecipePatchBody: Encodable, Equatable, Sendable {
    var name: String?
    var servings: String?
    var totalTime: String?
    var description: String?
    var instructions: [String]?
    /// Alle ingrediëntregels als tekst; ongewijzigde regels houden hun AH-koppeling.
    var ingredients: [String]?

    private enum CodingKeys: String, CodingKey {
        case name, servings, description, instructions, ingredients
        case totalTime = "total_time"
    }

    var isEmpty: Bool { self == RecipePatchBody() }
}
