import Foundation

// Plannings-API (docs/plan-api.md): planregels, vriezer, instellingen, volgende week.
// Er wordt nooit iets besteld: alleen het AH-lijstje bijwerken.
extension API {
    // MARK: Planregels

    /// Regels vanaf `start` voor `days` dagen (voor de dagchips).
    func planEntries(start: String, days: Int = 7) async throws -> PlanEntriesResponse {
        try await get("api/plan/entries", query: [URLQueryItem(name: "start", value: start),
                                                   URLQueryItem(name: "days", value: String(days))])
    }

    func createPlanEntry(_ body: PlanEntryCreateBody) async throws -> PlanCreateResponse {
        try await post("api/plan/entries", json: body)
    }

    func updatePlanEntry(_ entryID: Int, _ body: PlanEntryPatchBody) async throws -> PlanUpdateResponse {
        try await patch("api/plan/entries/\(entryID)", json: body)
    }

    func deletePlanEntry(_ entryID: Int) async throws -> PlanDeleteResponse {
        try await delete("api/plan/entries/\(entryID)")
    }

    // MARK: Boodschappen

    /// Zet de delta van de week (`status.missing`) op het AH-lijstje. Bestelt niets.
    /// Enige sync-pad: Weekmenu en "Wat eten we?" stap 3 gebruiken allebei deze call.
    func pushWeekToList(_ week: String) async throws -> SyncResult {
        try await post("api/plan/sync", json: WeekBody(week: week))
    }

    /// Lijst-link met personen per recept (dubbel koken = 2× personen).
    func listLink(recipeIDs: [Int], persons: [Int: Int]) async throws -> ListLinkResult {
        try await post("api/list-link", json: RecipePersonsBody(recipeIds: recipeIDs, persons: Self.personsKeys(persons)))
    }

    /// Producten in het AH-mandje met personen per recept. Bestelt niets.
    func fillBasket(recipeIDs: [Int], persons: [Int: Int]) async throws -> BasketFillResult {
        try await post("api/basket/fill", json: RecipePersonsBody(recipeIds: recipeIDs, persons: Self.personsKeys(persons)))
    }

    private static func personsKeys(_ persons: [Int: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: persons.map { (String($0.key), $0.value) })
    }

    // MARK: Week

    func weekHealth(_ week: String) async throws -> WeekHealth {
        try await get("api/week/health", query: [URLQueryItem(name: "week", value: week)])
    }

    /// Voorstel voor de lege dagen van een week. Slaat niets op.
    func suggestWeek(_ week: String) async throws -> SuggestResponse {
        try await post("api/week/suggest", json: WeekBody(week: week))
    }

    func nextWeekStatus() async throws -> NextWeekStatus {
        try await get("api/plan/next-week-status")
    }

    // MARK: Instellingen

    func planSettings() async throws -> PlanSettings {
        try await get("api/plan/settings")
    }

    func updatePlanSettings(_ body: PlanSettingsPatchBody) async throws -> PlanSettings {
        try await patch("api/plan/settings", json: body)
    }

    // MARK: Vriezer

    func freezerItems() async throws -> [FreezerItem] {
        let result: FreezerListResponse = try await get("api/freezer")
        return result.items
    }

    func addFreezerItem(name: String, portions: Int) async throws -> FreezerItemResponse {
        try await post("api/freezer", json: FreezerCreateBody(name: name, portions: portions))
    }

    /// `portions: 0` verwijdert het item.
    func setFreezerPortions(_ id: Int, portions: Int) async throws -> FreezerItemResponse {
        try await patch("api/freezer/\(id)", json: FreezerPortionsBody(portions: portions))
    }

    func deleteFreezerItem(_ id: Int) async throws {
        let _: OKResponse = try await delete("api/freezer/\(id)")
    }
}
