import Foundation

/// `GET /api/week/health`: variatie en gezondheid van de week.
struct WeekHealth: Decodable, Sendable {
    let dagen: Int
    let restjes: Int
    let gemiddeldKcal: Int?
    let groenteGPerDag: Int?
    let schijfPct: Int?
    let signalen: [HealthSignal]
    let recepten: [HealthRecipe]

    enum CodingKeys: String, CodingKey { case dagen, restjes, gemiddeldKcal, groenteGPerDag, schijfPct, signalen, recepten }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dagen = c.lenientInt(.dagen) ?? 0
        restjes = c.lenientInt(.restjes) ?? 0
        gemiddeldKcal = c.lenientInt(.gemiddeldKcal)
        groenteGPerDag = c.lenientInt(.groenteGPerDag)
        schijfPct = c.lenientInt(.schijfPct)
        signalen = c.lenient([HealthSignal].self, .signalen) ?? []
        recepten = c.lenient([HealthRecipe].self, .recepten) ?? []
    }

    /// Profiel per `entry_id`, voor de chips op de dagkaarten.
    var profilesByEntry: [Int: HealthProfile] {
        var out: [Int: HealthProfile] = [:]
        for r in recepten {
            if let id = r.entryId, let p = r.profiel { out[id] = p }
        }
        return out
    }
}
