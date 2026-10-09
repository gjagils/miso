import Foundation

/// Iets in de vriezer, met het aantal porties.
struct FreezerItem: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let portions: Int
    let addedOn: String?
    let fromRecipeId: Int?

    enum CodingKeys: String, CodingKey { case id, name, portions, addedOn, fromRecipeId }

    init(id: Int, name: String, portions: Int, addedOn: String? = nil, fromRecipeId: Int? = nil) {
        self.id = id
        self.name = name
        self.portions = portions
        self.addedOn = addedOn
        self.fromRecipeId = fromRecipeId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "vriezer-item zonder id")
        }
        self.init(id: id,
                  name: c.lenient(String.self, .name) ?? "",
                  portions: c.lenientInt(.portions) ?? 1,
                  addedOn: c.lenient(String.self, .addedOn),
                  fromRecipeId: c.lenientInt(.fromRecipeId))
    }
}
