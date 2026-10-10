import Foundation

/// Body voor `PATCH /api/recipes/{id}/flags`. Alleen meegestuurde velden veranderen.
struct RecipeFlagsBody: Encodable, Equatable {
    var favorite: Bool?
    var archived: Bool?
    var byHeart: Bool?
    /// "Bewaren" in de opruimlijst: een half jaar niet meer vragen.
    var reviewed: Bool?

    enum CodingKeys: String, CodingKey {
        case favorite, archived, reviewed
        case byHeart = "by_heart"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(favorite, forKey: .favorite)
        try c.encodeIfPresent(archived, forKey: .archived)
        try c.encodeIfPresent(byHeart, forKey: .byHeart)
        try c.encodeIfPresent(reviewed, forKey: .reviewed)
    }

    static let keep = RecipeFlagsBody(reviewed: true)
    static let byHeartKeep = RecipeFlagsBody(byHeart: true, reviewed: true)
    static let archive = RecipeFlagsBody(archived: true)
}
