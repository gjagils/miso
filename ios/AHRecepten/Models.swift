import Foundation

/// Glutenvrij voor minstens 1 persoon. Onbekende waarden van de server tellen als `.none`.
enum GlutenFreeMode: String, Decodable, Hashable {
    case none
    /// Extra glutenvrij product erbij (voor 1 persoon).
    case extra
    /// Ingrediënt voor iedereen vervangen.
    case replace

    var isActive: Bool { self != .none }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = GlutenFreeMode(rawValue: raw) ?? .none
    }
}

struct RecipeSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let servings: String
    let totalTime: String
    let imageUrl: String
    let gfMode: GlutenFreeMode
    /// Planregel waar dit recept bij hoort (alleen in `GET /api/week`, nieuwere servers).
    var entryId: Int? = nil
    /// Gebruik en voorkeur (`GET /api/recipes`, nieuwere servers; ontbreekt in planregels).
    var favorite: Bool? = nil
    var byHeart: Bool? = nil
    var archived: Bool? = nil
    /// "maaltijdpakket" voor AH-maaltijdpakketten, anders leeg.
    var collection: String? = nil

    var isFavorite: Bool { favorite ?? false }
    var isByHeart: Bool { byHeart ?? false }
    var isMealKit: Bool { collection == "maaltijdpakket" }
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
    /// Plek in de ingrediëntenlijst (nieuwere servers); nodig om één regel aan te passen.
    let index: Int?
    /// Door het gezin gekozen product (wordt nooit automatisch overschreven).
    let manual: Bool?

    /// Er hangt een AH-product aan deze regel.
    var isMatched: Bool { !(product ?? "").isEmpty }

    /// Aantal verpakkingen (de server rekent dit uit; minimaal 1, net als de web-versie).
    var packs: Int {
        let q = Int((Double(quantity ?? "") ?? 0).rounded(.up))
        return q > 0 ? q : 1
    }

    enum CodingKeys: String, CodingKey {
        case text, skip, gluten, gfSearch, product, gfProduct, quantity, pantry, unitSize
        case productId, productImage, gfProductId, index, manual
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
        index = Self.lenientInt(c, .index)
        manual = try? c.decodeIfPresent(Bool.self, forKey: .manual)
        if let s = try? c.decodeIfPresent(String.self, forKey: .quantity) {
            quantity = s
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .quantity) {
            quantity = d == d.rounded() ? String(Int(d)) : String(d)
        } else {
            quantity = nil
        }
    }
}

struct RecipeDetail: Decodable, Identifiable {
    let id: Int
    let name: String
    let servings: String
    let totalTime: String
    let imageUrl: String
    let gfMode: GlutenFreeMode
    let gfNote: String
    let description: String
    let sourceUrl: String
    let instructions: [String]
    /// `var`: één regel wordt na koppelen of uitvinken vervangen zonder het hele recept te herladen.
    var ingredients: [Ingredient]
    /// Voorkeur en gebruik (nieuwere servers). `var`: de knoppen op het recept passen ze direct aan.
    var favorite: Bool? = nil
    var byHeart: Bool? = nil
    var archived: Bool? = nil
    var collection: String? = nil
    var cookedCount: Int? = nil
    var thumbsUp: Int? = nil
    var thumbsDown: Int? = nil

    var isFavorite: Bool { favorite ?? false }
    var isByHeart: Bool { byHeart ?? false }
    var isArchived: Bool { archived ?? false }
    var isMealKit: Bool { collection == "maaltijdpakket" }
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
    /// Nieuwere servers: aantal producten dat nog niet op het AH-lijstje staat, en wat er al op staat.
    let missingCount: Int?
    let onList: Int?

    /// Hoeveel producten de knop "Zet N nieuwe producten op je AH-lijstje" zet.
    var newCount: Int { missingCount ?? missing.count }
}

struct PlanDay: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let label: String
    let today: Bool
    let recipes: [RecipeSummary]
    /// Alle planregels (recept, restje, voorraad); nil bij oudere servers.
    let items: [PlanItem]?

    enum CodingKeys: String, CodingKey {
        case date, label, today, recipes
        case items = "entries"
    }

    /// Planregels van deze dag; bij een oudere server opgebouwd uit `recipes`.
    func planItems(householdSize: Int) -> [PlanItem] {
        items ?? entries.map { PlanItem(legacy: $0.recipe, date: date, id: $0.id, persons: householdSize) }
    }
}

/// Eén recept op een dag in het weekmenu. De server stuurt geen eigen id per regel, dus het id is
/// datum + recept-id + hoeveelste keer dat recept die dag voorkomt; zo blijft het stabiel als er iets
/// anders op die dag bijkomt of verdwijnt.
struct PlanEntry: Identifiable {
    let id: String
    let recipe: RecipeSummary

    static func entries(date: String, recipes: [RecipeSummary]) -> [PlanEntry] {
        var seen: [Int: Int] = [:]
        return recipes.map { recipe in
            let n = seen[recipe.id, default: 0]
            seen[recipe.id] = n + 1
            return PlanEntry(id: "\(date)/\(recipe.id)/\(n)", recipe: recipe)
        }
    }
}

extension PlanDay {
    var entries: [PlanEntry] { PlanEntry.entries(date: date, recipes: recipes) }
}

struct WeekResponse: Decodable {
    let week: String
    let prevWeek: String
    let nextWeek: String
    let days: [PlanDay]
    let status: WeekStatus
    /// Nieuwere servers: standaard aantal personen.
    let householdSize: Int?
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
    /// Naam van het nieuwe recept (nieuwere servers).
    let name: String?
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
