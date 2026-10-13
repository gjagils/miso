import Foundation

/// Soort smaak: "lust geen" of "is dol op".
enum TasteKind: String, CaseIterable, Identifiable, Sendable {
    case dislike, like

    var id: String { rawValue }
    var title: String { self == .dislike ? "lust geen" : "is dol op" }
    var chipText: String { self == .dislike ? "lust geen" : "dol op" }
}

/// Eén voorkeur van een gezinslid (`/api/preferences`).
struct TastePreference: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let memberId: String
    let term: String
    let kind: TasteKind

    enum CodingKeys: String, CodingKey { case id, memberId, term, kind }

    init(id: Int, memberId: String, term: String, kind: TasteKind) {
        self.id = id
        self.memberId = memberId
        self.term = term
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        memberId = c.lenient(String.self, .memberId) ?? ""
        term = c.lenient(String.self, .term) ?? ""
        kind = TasteKind(rawValue: c.lenient(String.self, .kind) ?? "") ?? .dislike
    }
}

struct TasteMember: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let preferences: [TastePreference]

    enum CodingKeys: String, CodingKey { case id, name, preferences }

    init(id: String, name: String, preferences: [TastePreference] = []) {
        self.id = id
        self.name = name
        self.preferences = preferences
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.lenient(String.self, .name) ?? id
        preferences = c.lenient([TastePreference].self, .preferences) ?? []
    }
}

/// "Hannah lust waarschijnlijk geen paprika" (uit 👎): bevestigen of wegwuiven.
struct TasteSuggestion: Decodable, Identifiable, Equatable, Sendable {
    let memberId: String
    let name: String
    let term: String
    let down: Int
    let up: Int

    var id: String { "\(memberId):\(term)" }

    enum CodingKeys: String, CodingKey { case memberId, name, term, down, up }

    init(memberId: String, name: String, term: String, down: Int = 2, up: Int = 0) {
        self.memberId = memberId
        self.name = name
        self.term = term
        self.down = down
        self.up = up
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = c.lenient(String.self, .memberId) ?? ""
        name = c.lenient(String.self, .name) ?? ""
        term = c.lenient(String.self, .term) ?? ""
        down = c.lenientInt(.down) ?? 0
        up = c.lenientInt(.up) ?? 0
    }

    var detail: String { up > 0 ? "\(down)× 👎, \(up)× 👍" : "\(down)× 👎" }
}

struct TasteResponse: Decodable, Equatable, Sendable {
    let ok: Bool
    let error: String?
    let members: [TasteMember]
    let suggestions: [TasteSuggestion]

    enum CodingKeys: String, CodingKey { case ok, error, members, suggestions }

    init(ok: Bool = true, error: String? = nil, members: [TasteMember] = [], suggestions: [TasteSuggestion] = []) {
        self.ok = ok
        self.error = error
        self.members = members
        self.suggestions = suggestions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        error = c.lenient(String.self, .error)
        members = c.lenient([TasteMember].self, .members) ?? []
        suggestions = c.lenient([TasteSuggestion].self, .suggestions) ?? []
    }
}

struct TasteBody: Encodable, Equatable {
    let term: String
    let kind: String
}

struct TasteDismissBody: Encodable, Equatable {
    let memberId: String
    let term: String

    enum CodingKeys: String, CodingKey {
        case term
        case memberId = "member_id"
    }
}
