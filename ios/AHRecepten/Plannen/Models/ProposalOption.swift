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

    enum CodingKeys: String, CodingKey { case recipeId, ahRecipeId, name, imageUrl, totalTime, favorite, allerhande }

    init(recipeId: Int? = nil, ahRecipeId: Int? = nil, name: String, imageUrl: String = "", totalTime: String = "",
         favorite: Bool = false, allerhande: Bool = false) {
        self.recipeId = recipeId
        self.ahRecipeId = ahRecipeId
        self.name = name
        self.imageUrl = imageUrl
        self.totalTime = totalTime
        self.favorite = favorite
        self.allerhande = allerhande
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
    }

    /// "25 min · Allerhande"
    var meta: String {
        [totalTime, allerhande ? "Allerhande" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
