import Foundation

/// Gekookt recept in de weekanalyse; `entry_id` koppelt het profiel aan een dag.
struct HealthRecipe: Decodable, Sendable {
    let date: String
    let entryId: Int?
    let recipeId: Int?
    let name: String
    let profiel: HealthProfile?

    enum CodingKeys: String, CodingKey { case date, entryId, recipeId, name, profiel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.lenient(String.self, .date) ?? ""
        entryId = c.lenientInt(.entryId)
        recipeId = c.lenientInt(.recipeId)
        name = c.lenient(String.self, .name) ?? ""
        profiel = c.lenient(HealthProfile.self, .profiel)
    }
}
