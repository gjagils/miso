import Foundation

/// `POST /api/week/suggest`: voorstel voor de lege dagen. Slaat niets op.
struct SuggestResponse: Decodable, Sendable {
    let voorstel: [MenuSuggestion]
    /// Aantal recepten zonder profiel (Miso kent ze nog niet goed genoeg).
    let zonderProfiel: Int

    enum CodingKeys: String, CodingKey { case voorstel, zonderProfiel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voorstel = c.lenient([MenuSuggestion].self, .voorstel) ?? []
        zonderProfiel = c.lenientInt(.zonderProfiel) ?? 0
    }
}
