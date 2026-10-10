import Foundation

/// Recept op de opruimlijst (`GET /api/recipes-review`).
struct ReviewRecipe: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let imageUrl: String
    /// "Nog nooit gekozen", "Al 7 maanden niet gegeten", "Vaker 👎 dan 👍".
    let reason: String
    let planned: Int
    let cooked: Int
    let thumbsUp: Int
    let thumbsDown: Int
    let lastEaten: String?
    let ageDays: Int
    let byHeart: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, imageUrl, reason, planned, cooked, thumbsUp, thumbsDown, lastEaten, ageDays, byHeart
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(String.self, .name) ?? "Recept"
        imageUrl = c.lenient(String.self, .imageUrl) ?? ""
        reason = c.lenient(String.self, .reason) ?? ""
        planned = c.lenientInt(.planned) ?? 0
        cooked = c.lenientInt(.cooked) ?? 0
        thumbsUp = c.lenientInt(.thumbsUp) ?? 0
        thumbsDown = c.lenientInt(.thumbsDown) ?? 0
        lastEaten = c.lenient(String.self, .lastEaten).flatMap { $0.isEmpty ? nil : $0 }
        ageDays = c.lenientInt(.ageDays) ?? 0
        byHeart = c.lenient(Bool.self, .byHeart) ?? false
    }

    /// "Nog nooit gekozen · 0× gepland · 0× gekookt · 👍 1 👎 2 · laatst 3 mrt"
    var statsLine: String {
        var parts = [reason, "\(planned)× gepland", "\(cooked)× gekookt"].filter { !$0.isEmpty }
        if thumbsUp > 0 || thumbsDown > 0 { parts.append("👍 \(thumbsUp) 👎 \(thumbsDown)") }
        if let lastEaten { parts.append("laatst \(KiezenDates.short(lastEaten))") }
        return parts.joined(separator: " · ")
    }
}

struct RecipesReviewResponse: Decodable, Sendable {
    let totalPlans: Int
    let recipes: [ReviewRecipe]

    enum CodingKeys: String, CodingKey { case totalPlans, recipes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalPlans = c.lenientInt(.totalPlans) ?? 0
        recipes = c.lenient([ReviewRecipe].self, .recipes) ?? []
    }
}
