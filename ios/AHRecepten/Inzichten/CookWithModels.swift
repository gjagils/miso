import Foundation

/// Een ingrediënt dat al in huis is, en waar het vandaan komt ("vriezer" of "gekocht").
struct CookWithMatch: Decodable, Hashable, Sendable {
    let ingredient: String
    let from: String
    let source: String

    var isFreezer: Bool { source == "vriezer" }

    enum CodingKeys: String, CodingKey { case ingredient, from, source }

    init(ingredient: String, from: String, source: String) {
        self.ingredient = ingredient
        self.from = from
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ingredient: c.lenient(String.self, .ingredient) ?? "",
                  from: c.lenient(String.self, .from) ?? "",
                  source: c.lenient(String.self, .source) ?? "gekocht")
    }
}

/// Eigen recept dat grotendeels kan van wat er is, `GET /api/cook-with`.
struct CookWithSuggestion: Decodable, Identifiable, Hashable, Sendable {
    let recipeId: Int
    let name: String
    let imageUrl: String
    let totalTime: String
    let servings: String
    let covered: Int
    let total: Int
    let missingCount: Int
    let matches: [CookWithMatch]

    var id: Int { recipeId }

    enum CodingKeys: String, CodingKey {
        case recipeId, name, imageUrl, totalTime, servings, covered, total, missingCount, matches
    }

    init(recipeId: Int, name: String, imageUrl: String = "", totalTime: String = "", servings: String = "",
         covered: Int, total: Int, missingCount: Int, matches: [CookWithMatch] = []) {
        self.recipeId = recipeId
        self.name = name
        self.imageUrl = imageUrl
        self.totalTime = totalTime
        self.servings = servings
        self.covered = covered
        self.total = total
        self.missingCount = missingCount
        self.matches = matches
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.recipeId) else {
            throw DecodingError.dataCorruptedError(forKey: .recipeId, in: c, debugDescription: "voorstel zonder recept")
        }
        let matches = c.lenient([CookWithMatch].self, .matches) ?? []
        self.init(recipeId: id, name: c.lenient(String.self, .name) ?? "",
                  imageUrl: c.lenient(String.self, .imageUrl) ?? "", totalTime: c.lenient(String.self, .totalTime) ?? "",
                  servings: c.lenient(String.self, .servings) ?? "", covered: c.lenientInt(.covered) ?? matches.count,
                  total: c.lenientInt(.total) ?? 0, missingCount: c.lenientInt(.missingCount) ?? 0, matches: matches)
    }

    /// "Nog 1 ingrediënt nodig · 45 min" of "Alles al in huis".
    var detail: String {
        let need = missingCount == 0 ? "Alles al in huis"
            : "Nog \(missingCount) \(missingCount == 1 ? "ingrediënt" : "ingrediënten") nodig"
        return totalTime.isEmpty ? need : "\(need) · \(totalTime)"
    }

    /// "gehakt (vriezer), courgette (gekocht)".
    var haveText: String {
        matches.map { "\($0.ingredient) (\($0.isFreezer ? "vriezer" : "gekocht"))" }.joined(separator: ", ")
    }
}

struct CookWithResponse: Decodable, Sendable {
    let suggestions: [CookWithSuggestion]

    enum CodingKeys: String, CodingKey { case suggestions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = c.lenient([CookWithSuggestion].self, .suggestions) ?? []
    }
}
