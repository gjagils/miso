import Foundation

/// `PATCH /api/recipes/{id}/flags`.
struct RecipeFlagsResponse: Decodable, Sendable {
    let ok: Bool
    let recipe: RecipeSummary?
}

/// `POST /api/recipes/{id}/feedback`.
struct RecipeFeedbackResponse: Decodable, Sendable {
    let ok: Bool
    let thumbsUp: Int?
    let thumbsDown: Int?
    /// Je stem van vandaag (nieuwere servers): één per recept per dag, om te zetten.
    let rating: TasteRating?
}

/// `POST /api/recipes/{id}/cooked`.
struct RecipeCookedResponse: Decodable, Sendable {
    let ok: Bool
    let cooked: Int?
}

/// "Lekker?" na het koken.
enum TasteRating: String, Codable, Sendable {
    case up, down
}

struct RecipeFeedbackBody: Encodable {
    let rating: TasteRating
}
