import Foundation

/// `GET /api/members`: wie er in het gezin zit, wie er nu tikt (header) en of AH gekoppeld is.
struct MembersResponse: Decodable, Sendable {
    let members: [Member]
    let current: Member?
    /// nil bij servers die het nog niet meesturen.
    let ahConnected: Bool?

    enum CodingKeys: String, CodingKey { case members, current, ahConnected }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        members = c.lenient([Member].self, .members) ?? []
        current = c.lenient(Member.self, .current)
        ahConnected = c.lenient(Bool.self, .ahConnected)
    }
}

/// `PUT /api/members` (alleen ouders).
struct MembersSaveResponse: Decodable, Sendable {
    let ok: Bool
    let members: [Member]
}
