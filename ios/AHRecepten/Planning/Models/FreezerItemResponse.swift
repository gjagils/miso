import Foundation

/// `POST/PATCH /api/freezer[/id]` en `DELETE /api/freezer/{id}` (dan zonder item).
struct FreezerItemResponse: Decodable, Sendable {
    let ok: Bool
    let item: FreezerItem?
    let deleted: Bool

    enum CodingKeys: String, CodingKey { case ok, item, deleted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        item = c.lenient(FreezerItem.self, .item)
        deleted = c.lenient(Bool.self, .deleted) ?? false
    }
}
