import Foundation

/// Eén kant van een voorstel: een AH-product met de kosten voor dit recept.
struct CheaperSide: Decodable, Equatable, Sendable {
    let product: AHProduct
    let cost: Double
    let packs: Int

    init(product: AHProduct, cost: Double, packs: Int) {
        self.product = product
        self.cost = cost
        self.packs = packs
    }

    init(from decoder: Decoder) throws {
        // Het product en de kosten staan op hetzelfde niveau in het JSON-object.
        product = try AHProduct(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        cost = c.lenient(Double.self, .cost) ?? 0
        packs = c.lenientInt(.packs) ?? 1
    }

    private enum Keys: String, CodingKey { case cost, packs }
}

/// Eén goedkoper alternatief uit `POST /api/recipes/{id}/cheaper`.
struct CheaperSuggestion: Decodable, Identifiable, Equatable, Sendable {
    let index: Int
    let text: String
    let manual: Bool
    let current: CheaperSide
    let alternative: CheaperSide
    let saving: Double

    var id: Int { index }

    enum CodingKeys: String, CodingKey { case index, text, manual, current, alternative, saving }

    init(index: Int, text: String, manual: Bool = false, current: CheaperSide, alternative: CheaperSide, saving: Double) {
        self.index = index
        self.text = text
        self.manual = manual
        self.current = current
        self.alternative = alternative
        self.saving = saving
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        text = c.lenient(String.self, .text) ?? ""
        manual = c.lenient(Bool.self, .manual) ?? false
        current = try c.decode(CheaperSide.self, forKey: .current)
        alternative = try c.decode(CheaperSide.self, forKey: .alternative)
        saving = c.lenient(Double.self, .saving) ?? 0
    }
}

struct CheaperResponse: Decodable, Equatable, Sendable {
    let ok: Bool
    let error: String?
    let suggestions: [CheaperSuggestion]
    let totalSaving: Double

    enum CodingKeys: String, CodingKey { case ok, error, suggestions, totalSaving }

    init(ok: Bool = true, error: String? = nil, suggestions: [CheaperSuggestion] = [], totalSaving: Double = 0) {
        self.ok = ok
        self.error = error
        self.suggestions = suggestions
        self.totalSaving = totalSaving
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        error = c.lenient(String.self, .error)
        suggestions = c.lenient([CheaperSuggestion].self, .suggestions) ?? []
        totalSaving = c.lenient(Double.self, .totalSaving) ?? 0
    }
}
