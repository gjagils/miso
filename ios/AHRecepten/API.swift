import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ServerError: Decodable { let error: String? }

struct API {
    let baseURL: URL
    let token: String

    /// Gedeelde decoder (snake_case -> camelCase); ook gebruikt door de tests.
    static let decoder: JSONDecoder = {
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

    private func request(_ path: String, method: String, query: [URLQueryItem] = []) throws -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        guard url.scheme != nil else { throw APIError(message: "Ongeldig serveradres") }
        var req = URLRequest(url: url)
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
            if msg == nil && status == 422 { throw APIError(message: "Controleer de invoer.") }
            throw APIError(message: msg ?? "Serverfout (HTTP \(status))")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(try request(path, method: "GET", query: query))
    }

    func post<T: Decodable>(_ path: String, json body: some Encodable) async throws -> T {
        try await send(path, method: "POST", json: body)
    }

    func patch<T: Decodable>(_ path: String, json body: some Encodable) async throws -> T {
        try await send(path, method: "PATCH", json: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send(try request(path, method: "DELETE"))
    }

    private func send<T: Decodable>(_ path: String, method: String, json body: some Encodable) async throws -> T {
        var req = try request(path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req)
    }

    func post<T: Decodable>(_ path: String, form: [String: String] = [:]) async throws -> T {
        var req = try request(path, method: "POST")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        req.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        return try await send(req)
    }

    /// Bestand voor een multipart-upload.
    struct UploadFile {
        let data: Data
        let filename: String
        let mimeType: String
    }

    /// Recept importeren uit een link, tekst en/of foto's.
    /// - Parameters:
    ///   - url: pagina die de server zelf ophaalt (leeg laten als de site de server blokkeert).
    ///   - images: foto's waar Claude het recept uit leest.
    ///   - sourceURL: bronlink die alleen bewaard wordt (de server haalt hem niet op).
    ///   - imageURL: receptfoto op de site; de server haalt alleen die foto op.
    ///   - photo: receptfoto die het toestel al heeft gedownload (wordt de receptfoto, gaat niet naar Claude).
    func importRecipe(url: String, text: String, images: [Data], sourceURL: String = "", imageURL: String = "",
                      photo: UploadFile? = nil) async throws -> ImportResult {
        var req = try request("api/import", method: "POST")
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        func file(_ name: String, _ file: UploadFile) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(file.filename)\"\r\nContent-Type: \(file.mimeType)\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }
        field("url", url)
        field("text", text)
        if !sourceURL.isEmpty { field("source_url", sourceURL) }
        if !imageURL.isEmpty { field("image_url", imageURL) }
        for (i, img) in images.enumerated() {
            file("images", UploadFile(data: img, filename: "foto\(i).jpg", mimeType: "image/jpeg"))
        }
        if let photo { file("photo", photo) }
        body.append(Data("--\(boundary)--\r\n".utf8))
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

    /// Actieve AH-bestelling (mandje); zonder gekozen bezorgmoment is er geen order_id.
    func basketStatus() async throws -> BasketStatus {
        try await get("api/basket")
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
