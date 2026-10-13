import Foundation
import Testing
@testable import AHRecepten

struct TasteDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func tasteOverview() throws {
        let r = try decode(TasteResponse.self, #"""
        {"ok": true,
         "members": [{"id": "hannah", "name": "Hannah", "role": "kind", "color": "#F00",
                      "preferences": [{"id": 4, "member_id": "hannah", "term": "paprika", "kind": "dislike"},
                                      {"id": 5, "member_id": "hannah", "term": "kip", "kind": "like"}]},
                     {"id": "suze", "name": "Suze", "preferences": []}],
         "suggestions": [{"member_id": "hannah", "name": "Hannah", "term": "koriander", "down": 3, "up": 1}]}
        """#)
        #expect(r.members.count == 2 && r.members[0].preferences.count == 2 && r.members[1].preferences.isEmpty)
        #expect(r.members[0].preferences[0].kind == .dislike && r.members[0].preferences[1].kind == .like)
        #expect(r.suggestions.first?.id == "hannah:koriander" && r.suggestions.first?.detail == "3× 👎, 1× 👍")
        let bare = try decode(TasteResponse.self, #"{"ok": false, "error": "Dit gezinslid bestaat niet."}"#)
        #expect(!bare.ok && bare.error == "Dit gezinslid bestaat niet." && bare.members.isEmpty)
        let unknown = try decode(TastePreference.self, #"{"id": 1, "member_id": "x", "term": "ui", "kind": "haat"}"#)
        #expect(unknown.kind == .dislike)  // onbekende soort valt terug op afkeer
    }

    @Test func bodies() throws {
        let body = try JSONEncoder().encode(TasteBody(term: "paprika", kind: TasteKind.like.rawValue))
        #expect(String(data: body, encoding: .utf8)?.contains("\"kind\":\"like\"") == true)
        let dismiss = try JSONEncoder().encode(TasteDismissBody(memberId: "hannah", term: "koriander"))
        let json = try #require(JSONSerialization.jsonObject(with: dismiss) as? [String: Any])
        #expect(json["member_id"] as? String == "hannah" && json["term"] as? String == "koriander")
        #expect(TasteKind.dislike.title == "lust geen" && TasteKind.like.chipText == "dol op")
    }

    @Test func proposalOptionWarnings() throws {
        let o = try decode(ProposalOption.self, #"""
        {"recipe_id": 3, "name": "Rijst met paprika", "avoid": ["Hannah lust geen paprika"], "bonus_saving": 0}
        """#)
        #expect(o.avoid == ["Hannah lust geen paprika"])
        let old = try decode(ProposalOption.self, #"{"recipe_id": 3, "name": "Pasta"}"#)
        #expect(old.avoid.isEmpty)
    }
}
