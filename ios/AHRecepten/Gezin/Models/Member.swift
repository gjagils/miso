import Foundation

/// Gezinslid uit `GET /api/members` ("Wie ben jij?"). Een ouder mag alles, een kind geeft wensen door.
struct Member: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let role: MemberRole
    /// Eerste letter van de naam (zo staat hij ook bij de favorieten: `fans`).
    let initial: String
    /// "#RRGGBB"
    let color: String
    /// "/avatar/<id>?v=…" (achter de pincode) of leeg: dan de initiaal.
    let avatarUrl: String

    var isKid: Bool { role == .kind }

    enum CodingKeys: String, CodingKey { case id, name, role, initial, color, avatarUrl }

    init(id: String, name: String, role: MemberRole, initial: String? = nil, color: String = "#FF8A00",
         avatarUrl: String = "") {
        self.id = id
        self.name = name
        self.role = role
        self.initial = initial ?? String(name.prefix(1)).uppercased()
        self.color = color
        self.avatarUrl = avatarUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.lenient(String.self, .name) ?? id
        role = c.lenient(MemberRole.self, .role) ?? .ouder
        initial = c.lenient(String.self, .initial) ?? String(name.prefix(1)).uppercased()
        color = c.lenient(String.self, .color) ?? "#FF8A00"
        avatarUrl = c.lenient(String.self, .avatarUrl) ?? ""
    }
}
