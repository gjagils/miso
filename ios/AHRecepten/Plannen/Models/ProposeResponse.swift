import Foundation

/// `POST /api/plan/propose`: per dag het beste recept plus alternatieven.
struct ProposeResponse: Decodable, Sendable {
    let ok: Bool
    let week: String
    let days: [ProposalDay]

    enum CodingKeys: String, CodingKey { case ok, week, days }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        week = c.lenient(String.self, .week) ?? ""
        days = c.lenient([ProposalDay].self, .days) ?? []
    }
}
