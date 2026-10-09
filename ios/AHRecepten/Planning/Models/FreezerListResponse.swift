import Foundation

/// `GET /api/freezer`: items met porties > 0, oudste eerst.
struct FreezerListResponse: Decodable, Sendable {
    let items: [FreezerItem]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lenient([FreezerItem].self, .items) ?? []
    }
}
