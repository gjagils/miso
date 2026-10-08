import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ServerError: Decodable { let error: String? }

struct API {
    let baseURL: URL
    let token: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Absolute URL for an image path that is either relative ("/image/3") or already absolute.
    func imageURL(_ path: String) -> URL? {
        if path.isEmpty { return nil }
        if path.hasPrefix("/") { return URL(string: path, relativeTo: baseURL)?.absoluteURL }
        return URL(string: path)
    }

    private func request(_ path: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 120 // Claude kan even bezig zijn
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw APIError(message: "Niet ingelogd of verkeerde pincode.") }
            let msg = (try? Self.decoder.decode(ServerError.self, from: data))?.error
            throw APIError(message: msg ?? "Serverfout (HTTP \(status))")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(request(path, method: "GET", query: query))
    }

    func post<T: Decodable>(_ path: String, json body: some Encodable) async throws -> T {
        var req = request(path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let enc = JSONEncoder()
        req.httpBody = try enc.encode(body)
        return try await send(req)
    }

    func post<T: Decodable>(_ path: String, form: [String: String] = [:]) async throws -> T {
        var req = request(path, method: "POST")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    /// Recept importeren uit een link, tekst en/of foto's.
    func importRecipe(url: String, text: String, images: [Data]) async throws -> ImportResult {
        var req = request("api/import", method: "POST")
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("url", url)
        field("text", text)
        for (i, img) in images.enumerated() {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"images\"; filename=\"foto\(i).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(img)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await send(req)
    }

    /// Login zonder bestaande token (pincode -> token).
    static func login(baseURL: URL, pin: String) async throws -> String {
        struct Body: Encodable { let pin: String }
        struct Result: Decodable { let token: String }
        let result: Result = try await API(baseURL: baseURL, token: "").post("api/login", json: Body(pin: pin))
        return result.token
    }
}

// MARK: - Wat eten we? (dezelfde endpoints en payloads als backend/app/templates/kiezen.html)

extension API {
    /// Eigen recepten, gefilterd op naam (lege zoekterm = alles).
    func recipes(query: String = "") async throws -> [RecipeSummary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let items = q.isEmpty ? [] : [URLQueryItem(name: "q", value: q)]
        let result: RecipesResponse = try await get("api/recipes", query: items)
        return result.recipes
    }

    func recipe(id: Int) async throws -> RecipeDetail {
        try await get("api/recipes/\(id)")
    }

    func searchAllerhande(_ query: String) async throws -> [AHRecipeHit] {
        let result: AHSearchResponse = try await get(
            "api/allerhande/search", query: [URLQueryItem(name: "q", value: query)]
        )
        return result.results
    }

    /// Allerhande-recept in de eigen bibliotheek zetten (form: recipe_id). Bestaat het al, dan komt het bestaande id terug.
    func addAllerhande(id: Int) async throws -> AddResult {
        try await post("api/allerhande/add", form: ["recipe_id": String(id)])
    }

    func week(_ start: String?) async throws -> WeekResponse {
        try await get("api/week", query: start.map { [URLQueryItem(name: "week", value: $0)] } ?? [])
    }

    /// Hele week opslaan: {week, days: {"YYYY-MM-DD": [recipe ids]}}.
    func savePlan(week: String, days: [String: [Int]]) async throws -> SavePlanResult {
        try await post("api/plan", json: SavePlanBody(week: week, days: days))
    }

    /// Zet wat de week nog nodig heeft op het AH-lijstje; met locked=true wordt de week ook vastgezet.
    func syncWeek(_ week: String, locked: Bool?) async throws -> SyncResult {
        try await post("api/plan/sync", json: SyncBody(week: week, locked: locked))
    }

    /// Producten van deze recepten in het AH-mandje zetten. Bestelt niets.
    func fillBasket(recipeIDs: [Int]) async throws -> BasketFillResult {
        try await post("api/basket/fill", json: RecipeIDsBody(recipeIds: recipeIDs))
    }

    /// Haalt weg wat Miso in het mandje zette. Bestelt niets.
    func clearBasket() async throws -> BasketClearResult {
        try await post("api/basket/clear", json: EmptyBody())
    }

    /// ah.nl-link die de (samengevoegde) producten via de eigen AH-sessie op 'Mijn lijst' zet.
    func listLink(recipeIDs: [Int]) async throws -> ListLinkResult {
        try await post("api/list-link", json: RecipeIDsBody(recipeIds: recipeIDs))
    }
}
