import Foundation

/// Eén voorgesteld recept: eigen recept (`recipeId`) of Allerhande (`ahRecipeId`, wordt bij bevestigen geïmporteerd).
struct ProposalOption: Decodable, Hashable, Sendable {
    let recipeId: Int?
    let ahRecipeId: Int?
    let name: String
    let imageUrl: String
    let totalTime: String
    let favorite: Bool
    let allerhande: Bool
    /// AH-maaltijdpakket (de server stuurt de korte naam, zonder "AH verspakket").
    let pack: Bool
    /// Profiel voor de week-check ("vega", "vis", "kip", "vlees"; "italiaans"; "rijst"). Mag leeg zijn.
    let eiwit: String
    let keuken: String
    let basis: String
    /// Geschat voordeel in euro's als ingrediënten in de bonus van die week zitten; 0 = geen bonus.
    let bonusSaving: Double
    /// Iemand in het gezin wil dit graag (open wens).
    let wished: Bool
    /// Waarschuwingen: "Hannah lust geen paprika". Leeg = niets aan de hand.
    let avoid: [String]

    enum CodingKeys: String, CodingKey {
        case recipeId, ahRecipeId, name, imageUrl, totalTime, favorite, allerhande, pack, eiwit, keuken, basis
        case bonusSaving, wished, avoid
    }

    init(recipeId: Int? = nil, ahRecipeId: Int? = nil, name: String, imageUrl: String = "", totalTime: String = "",
         favorite: Bool = false, allerhande: Bool = false, pack: Bool = false,
         eiwit: String = "", keuken: String = "", basis: String = "", bonusSaving: Double = 0, wished: Bool = false, avoid: [String] = []) {
        self.avoid = avoid
        self.bonusSaving = bonusSaving
        self.wished = wished
        self.eiwit = eiwit
        self.keuken = keuken
        self.basis = basis
        self.recipeId = recipeId
        self.ahRecipeId = ahRecipeId
        self.name = name
        self.imageUrl = imageUrl
        self.totalTime = totalTime
        self.favorite = favorite
        self.allerhande = allerhande
        self.pack = pack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipeId = c.lenientInt(.recipeId)
        ahRecipeId = c.lenientInt(.ahRecipeId)
        name = c.lenient(String.self, .name) ?? "Recept"
        imageUrl = c.lenient(String.self, .imageUrl) ?? ""
        totalTime = c.lenient(String.self, .totalTime) ?? ""
        favorite = c.lenient(Bool.self, .favorite) ?? false
        allerhande = c.lenient(Bool.self, .allerhande) ?? (recipeId == nil && ahRecipeId != nil)
        pack = c.lenient(Bool.self, .pack) ?? false
        eiwit = c.lenient(String.self, .eiwit) ?? ""
        keuken = c.lenient(String.self, .keuken) ?? ""
        basis = c.lenient(String.self, .basis) ?? ""
        bonusSaving = c.lenient(Double.self, .bonusSaving) ?? 0
        wished = c.lenient(Bool.self, .wished) ?? false
        avoid = c.lenient([String].self, .avoid) ?? []
    }

    /// "25 min · Allerhande"
    var meta: String {
        [totalTime, allerhande ? "Allerhande" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
