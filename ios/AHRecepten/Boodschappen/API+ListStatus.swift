import Foundation

extension API {
    /// Laatst opgeslagen lijststatus van een week (zonder AH te vragen). `check: true` leest AH één keer
    /// (alleen na de knop "Controleer met AH").
    func listStatus(week: String, check: Bool = false) async throws -> ListStatus {
        var query = [URLQueryItem(name: "week", value: week)]
        if check { query.append(URLQueryItem(name: "check", value: "1")) }
        return try await get("api/plan/list-status", query: query)
    }
}
