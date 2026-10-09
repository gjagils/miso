import Foundation

struct RecipeSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let servings: String
    let totalTime: String
    let imageUrl: String
    let gfMode: String
}

struct RecipesResponse: Decodable { let recipes: [RecipeSummary] }

struct Ingredient: Decodable, Identifiable {
    var id: String { text }
    let text: String
    let skip: Bool
    let gluten: Bool
    let gfSearch: String
    let product: String?
    let gfProduct: String?
    /// Optioneel: oudere servers sturen deze velden niet mee.
    let quantity: String?
    let pantry: Bool?
    let unitSize: String?
    let productId: Int?
    let productImage: String?
    let gfProductId: Int?

    /// Aantal verpakkingen (de server rekent dit uit; minimaal 1, net als de web-versie).
    var packs: Int {
        let q = Int((Double(quantity ?? "") ?? 0).rounded(.up))
        return q > 0 ? q : 1
    }

    enum CodingKeys: String, CodingKey {
        case text, skip, gluten, gfSearch, product, gfProduct, quantity, pantry, unitSize
        case productId, productImage, gfProductId
    }

    private static func lenientInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        skip = try c.decode(Bool.self, forKey: .skip)
        gluten = try c.decode(Bool.self, forKey: .gluten)
        gfSearch = try c.decode(String.self, forKey: .gfSearch)
        product = try? c.decodeIfPresent(String.self, forKey: .product)
        gfProduct = try? c.decodeIfPresent(String.self, forKey: .gfProduct)
        pantry = try? c.decodeIfPresent(Bool.self, forKey: .pantry)
        unitSize = try? c.decodeIfPresent(String.self, forKey: .unitSize)
        productId = Self.lenientInt(c, .productId)
        productImage = try? c.decodeIfPresent(String.self, forKey: .productImage)
        gfProductId = Self.lenientInt(c, .gfProductId)
        if let s = try? c.decodeIfPresent(String.self, forKey: .quantity) {
            quantity = s
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .quantity) {
            quantity = d == d.rounded() ? String(Int(d)) : String(d)
        } else {
            quantity = nil
        }
    }
}

struct RecipeDetail: Decodable {
    let id: Int
    let name: String
    let servings: String
    let totalTime: String
    let imageUrl: String
    let gfMode: String
    let gfNote: String
    let description: String
    let sourceUrl: String
    let instructions: [String]
    let ingredients: [Ingredient]
}

struct MissingItem: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let quantity: Int
}

struct WeekStatus: Decodable {
    let needed: Int
    let missing: [MissingItem]
    let unmatched: [String]
    let complete: Bool
    let locked: Bool
}

struct PlanDay: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let label: String
    let today: Bool
    let recipes: [RecipeSummary]
}

struct WeekResponse: Decodable {
    let week: String
    let prevWeek: String
    let nextWeek: String
    let days: [PlanDay]
    let status: WeekStatus
}

struct SavePlanBody: Encodable {
    let week: String
    let days: [String: [Int]]
}

struct SavePlanResult: Decodable { let ok: Bool }

struct SyncBody: Encodable {
    let week: String
    let locked: Bool?
}

struct SyncResult: Decodable {
    let ok: Bool
    let added: Int?
    let error: String?
    let status: WeekStatus?
}

struct ImportResult: Decodable {
    let ok: Bool
    let id: Int?
    let error: String?
}

struct AHRecipeHit: Decodable, Identifiable {
    let id: Int
    let title: String
    let servings: String
    let url: String
    /// Optioneel: oudere servers sturen deze velden niet mee.
    let time: String?
    let imageUrl: String?
    var saved: Bool
}

struct AHSearchResponse: Decodable { let results: [AHRecipeHit] }

struct AddResult: Decodable {
    let ok: Bool
    let id: Int?
    let error: String?
}

struct GlutenSuggestResult: Decodable {
    let ok: Bool
    let error: String?
}

// MARK: - Wat eten we? (kiezen -> inplannen -> boodschappen)

struct RecipeIDsBody: Encodable {
    let recipeIds: [Int]
    enum CodingKeys: String, CodingKey { case recipeIds = "recipe_ids" }
}

struct EmptyBody: Encodable {}

struct BasketFillResult: Decodable {
    let ok: Bool
    let added: Int?
    let error: String?
}

struct BasketStatus: Decodable {
    let ok: Bool
    let orderId: Int?
    let delivery: String?
    enum CodingKeys: String, CodingKey { case ok, orderId = "order_id", delivery }
}

struct BasketClearResult: Decodable {
    let ok: Bool
    let removed: Int?
    let error: String?
}

struct ListLinkResult: Decodable {
    let ok: Bool
    let url: String
    let count: Int
}
