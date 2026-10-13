import Foundation

/// Eigen recept met ingrediënten in de bonus (`GET /api/bonus/recipes`).
struct BonusRecipe: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let imageUrl: String
    let servings: String
    let totalTime: String
    /// Hoeveel gekoppelde ingrediënten in de bonus zitten.
    let bonusCount: Int
    /// Geschat voordeel in euro's; nil als AH geen prijzen gaf.
    let saving: Double?

    enum CodingKeys: String, CodingKey { case id, name, imageUrl, servings, totalTime, bonusCount, saving }

    init(id: Int, name: String, imageUrl: String = "", servings: String = "", totalTime: String = "", bonusCount: Int = 1,
         saving: Double? = nil) {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.servings = servings
        self.totalTime = totalTime
        self.bonusCount = bonusCount
        self.saving = saving
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(String.self, .name) ?? "Recept"
        imageUrl = c.lenient(String.self, .imageUrl) ?? ""
        servings = c.lenient(String.self, .servings) ?? ""
        totalTime = c.lenient(String.self, .totalTime) ?? ""
        bonusCount = c.lenientInt(.bonusCount) ?? 0
        saving = c.lenient(Double.self, .saving)
    }

    /// "± € 2,80 voordeel" of de gewone meta (porties · tijd).
    var meta: String {
        if let saving, saving > 0 { return "± \(Euro.format(saving)) voordeel" }
        return [servings, totalTime].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct BonusPeriod: Decodable, Equatable, Sendable {
    let start: String
    let end: String

    enum CodingKeys: String, CodingKey { case start, end }

    init(start: String = "", end: String = "") {
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.lenient(String.self, .start) ?? ""
        end = c.lenient(String.self, .end) ?? ""
    }
}

struct BonusRecipesResponse: Decodable, Equatable, Sendable {
    let ok: Bool
    let period: BonusPeriod
    let recipes: [BonusRecipe]

    enum CodingKeys: String, CodingKey { case ok, period, recipes }

    init(ok: Bool = true, period: BonusPeriod = BonusPeriod(), recipes: [BonusRecipe] = []) {
        self.ok = ok
        self.period = period
        self.recipes = recipes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? false
        period = c.lenient(BonusPeriod.self, .period) ?? BonusPeriod()
        recipes = c.lenient([BonusRecipe].self, .recipes) ?? []
    }

    /// De bonus is van een latere week dan vandaag: "Volgende week in de bonus".
    func isNextWeek(today: String) -> Bool { !period.start.isEmpty && period.start > today }

    func title(today: String) -> String { isNextWeek(today: today) ? "Volgende week in de bonus" : "Deze week in de bonus" }

    /// "Aanbiedingen t/m zondag 18 okt" (bij volgende week: "van maandag 12 okt t/m …")
    func subtitle(today: String) -> String {
        guard !period.end.isEmpty else { return "Recepten met aanbiedingen" }
        let end = KiezenDates.short(period.end)
        return isNextWeek(today: today) ? "Aanbiedingen van \(KiezenDates.short(period.start)) t/m \(end)" : "Aanbiedingen t/m \(end)"
    }
}
