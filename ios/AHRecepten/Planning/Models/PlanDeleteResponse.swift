import Foundation

/// `DELETE /api/plan/entries/{id}`: een kookdag neemt zijn rest-dagen mee.
struct PlanDeleteResponse: Decodable, Sendable {
    let ok: Bool
    let deleted: [Int]
    let status: WeekStatus?

    enum CodingKeys: String, CodingKey { case ok, deleted, status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        deleted = c.lenient([Int].self, .deleted) ?? []
        status = c.lenient(WeekStatus.self, .status)
    }
}
