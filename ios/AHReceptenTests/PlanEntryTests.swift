import Foundation
import Testing
@testable import AHRecepten

struct PlanEntryTests {
    @Test func idsAreUniqueAndStable() throws {
        let json = #"[{"id":1,"name":"A","servings":"","total_time":"","image_url":"","gf_mode":"none"},"#
            + #"{"id":2,"name":"B","servings":"","total_time":"","image_url":"","gf_mode":"weird"},"#
            + #"{"id":1,"name":"A","servings":"","total_time":"","image_url":"","gf_mode":"extra"}]"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let recipes = try decoder.decode([RecipeSummary].self, from: Data(json.utf8))

        let ids = PlanEntry.entries(date: "2025-10-06", recipes: recipes).map(\.id)
        #expect(ids == ["2025-10-06/1/0", "2025-10-06/2/0", "2025-10-06/1/1"])
        // B weghalen verandert de ids van de andere regels niet.
        let after = PlanEntry.entries(date: "2025-10-06", recipes: [recipes[0], recipes[2]]).map(\.id)
        #expect(after == ["2025-10-06/1/0", "2025-10-06/1/1"])

        // Onbekende gf_mode telt als "none".
        #expect(recipes.map(\.gfMode) == [.none, .none, .extra])
    }
}
