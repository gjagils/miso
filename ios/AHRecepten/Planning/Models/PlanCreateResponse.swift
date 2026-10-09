import Foundation

/// `POST /api/plan/entries`: wat er is aangemaakt (kookdag + eventuele rest-dag).
struct PlanCreateResponse: Decodable, Sendable {
    let ok: Bool
    let entries: [PlanItem]
    let freezerItem: FreezerItem?
    let status: WeekStatus?
    let error: String?

    enum CodingKeys: String, CodingKey { case ok, entries, freezerItem, status, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        entries = c.lenient([PlanItem].self, .entries) ?? []
        freezerItem = c.lenient(FreezerItem.self, .freezerItem)
        status = c.lenient(WeekStatus.self, .status)
        error = c.lenient(String.self, .error)
    }
}
