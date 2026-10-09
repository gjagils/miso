import Foundation

/// `GET /api/plan/entries`: regels in een periode (voor de dagchips).
struct PlanEntriesResponse: Decodable, Sendable {
    let start: String
    let end: String
    let householdSize: Int?
    let entries: [PlanItem]

    enum CodingKeys: String, CodingKey { case start, end, householdSize, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.lenient(String.self, .start) ?? ""
        end = c.lenient(String.self, .end) ?? ""
        householdSize = c.lenientInt(.householdSize)
        entries = c.lenient([PlanItem].self, .entries) ?? []
    }
}
