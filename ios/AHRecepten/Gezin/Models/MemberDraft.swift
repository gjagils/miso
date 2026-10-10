import Foundation

/// Gezinslid in de editor bij Meer → Gezinsleden (`PUT /api/members`). Zonder id = nieuw.
struct MemberDraft: Encodable, Identifiable, Hashable, Sendable {
    /// Id op de server; nil voor een nieuw lid (de server maakt er een van de naam).
    var serverID: String?
    var name: String
    var role: MemberRole
    /// Alleen voor de lijst op het toestel.
    let id: UUID

    init(serverID: String? = nil, name: String = "", role: MemberRole = .ouder, id: UUID = UUID()) {
        self.serverID = serverID
        self.name = name
        self.role = role
        self.id = id
    }

    init(_ member: Member) {
        self.init(serverID: member.id, name: member.name, role: member.role)
    }

    enum CodingKeys: String, CodingKey { case id, name, role }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(serverID, forKey: .id)
        try c.encode(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .name)
        try c.encode(role.rawValue, forKey: .role)
    }

    /// Opslaan mag als er minstens één ouder met een naam is (anders kan niemand meer plannen).
    static func canSave(_ drafts: [MemberDraft]) -> Bool {
        drafts.contains { $0.role == .ouder && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

struct MembersSaveBody: Encodable {
    let members: [MemberDraft]
}
