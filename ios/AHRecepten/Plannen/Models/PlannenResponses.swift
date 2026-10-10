import Foundation

/// `POST /api/plan/wishes-text`: wens per datum.
struct WishesTextResponse: Decodable, Sendable {
    let ok: Bool
    let wishes: [String: String]
    let error: String?

    enum CodingKeys: String, CodingKey { case ok, wishes, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        wishes = c.lenient([String: String].self, .wishes) ?? [:]
        error = c.lenient(String.self, .error)
    }
}

/// `POST /api/plan/apply`: hoeveel dagen er zijn ingepland.
struct PlanApplyResponse: Decodable, Sendable {
    let ok: Bool
    let added: Int
    let status: WeekStatus?
    let error: String?

    enum CodingKeys: String, CodingKey { case ok, added, status, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        added = c.lenientInt(.added) ?? 0
        status = c.lenient(WeekStatus.self, .status)
        error = c.lenient(String.self, .error)
    }
}
