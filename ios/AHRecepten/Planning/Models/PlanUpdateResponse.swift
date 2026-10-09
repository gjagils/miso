import Foundation

/// `PATCH /api/plan/entries/{id}`.
struct PlanUpdateResponse: Decodable, Sendable {
    let ok: Bool
    let entry: PlanItem?
    let status: WeekStatus?
    /// Weken die geraakt zijn (bij verplaatsen naar een andere week: beide).
    let weeks: [String]

    enum CodingKeys: String, CodingKey { case ok, entry, status, weeks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        entry = c.lenient(PlanItem.self, .entry)
        status = c.lenient(WeekStatus.self, .status)
        weeks = c.lenient([String].self, .weeks) ?? []
    }
}
