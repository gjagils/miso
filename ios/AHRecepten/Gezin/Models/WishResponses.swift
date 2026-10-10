import Foundation

/// `GET /api/wishes`, en het antwoord op toevoegen/klaar/weghalen (`{"ok", "wishes"}`).
struct WishesResponse: Decodable, Sendable {
    let ok: Bool
    let wishes: [FamilyWish]
    let error: String?

    enum CodingKeys: String, CodingKey { case ok, wishes, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        wishes = c.lenient([FamilyWish].self, .wishes) ?? []
        error = c.lenient(String.self, .error)
    }
}

/// `POST /api/wishes/{id}/to-list`: boodschappenwens op het AH-lijstje. Met `url` is AH niet gekoppeld
/// en opent de app die link (ah.nl zet het dan op je lijstje). Bestelt nooit iets.
struct WishToListResponse: Decodable, Sendable {
    let ok: Bool
    let product: String?
    let url: String?
    let wishes: [FamilyWish]?
    let error: String?

    enum CodingKeys: String, CodingKey { case ok, product, url, wishes, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? false
        product = c.lenient(String.self, .product)
        url = c.lenient(String.self, .url).flatMap { $0.isEmpty ? nil : $0 }
        wishes = c.lenient([FamilyWish].self, .wishes)
        error = c.lenient(String.self, .error)
    }
}

/// Body voor `POST /api/wishes`.
struct WishBody: Encodable, Equatable {
    var recipeId: Int?
    var text: String = ""
    var kind: WishKind = .eten

    enum CodingKeys: String, CodingKey {
        case text, kind
        case recipeId = "recipe_id"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(recipeId, forKey: .recipeId)
        try c.encode(text, forKey: .text)
        try c.encode(kind.rawValue, forKey: .kind)
    }
}
