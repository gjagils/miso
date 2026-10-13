import Foundation
import Testing
@testable import AHRecepten

struct VoteTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func pollDecodesAndDescribes() throws {
        let p = try decode(VotePoll.self, #"""
        {"ok": true, "week": "2026-10-19", "open": true, "max_votes": 3, "my_votes": 1, "voted_count": 2, "members_total": 4,
         "candidates": [{"recipe_id": 3, "name": "Stoofpot", "image_url": "", "total_time": "2 uur", "votes": 2,
                         "voters": ["G", "N"], "mine": true},
                        {"recipe_id": 4, "name": "Soep", "votes": 0}]}
        """#)
        #expect(p.open && p.candidates.count == 2 && p.candidates[0].mine && !p.candidates[1].mine)
        #expect(p.candidates[0].detail == "2 uur · 2 stemmen (G N)")
        #expect(p.candidates[1].detail == "0 stemmen")
        #expect(p.intro == "Stem op maximaal 3 recepten die je graag wilt eten. 2 van 4 hebben gestemd; jij gaf 1 van 3 stemmen.")
        let closed = try decode(VotePoll.self, #"{"ok": true, "open": false}"#)
        #expect(!closed.open && closed.candidates.isEmpty && closed.intro.hasPrefix("Laat het gezin kiezen"))
        let failed = try decode(VotePoll.self, #"{"ok": false, "error": "Je hebt al 3 stemmen uitgebracht."}"#)
        #expect(!failed.ok && failed.error?.contains("3 stemmen") == true)
    }

    @Test func closeSummary() throws {
        let r = try decode(VoteCloseResponse.self, #"{"ok": true, "placed": 1, "no_room": 2, "no_votes": 1}"#)
        #expect(r.summary == "1 dag gevuld, 2 recepten kon er niet meer bij, 1 recept zonder stem overgeslagen.")
        #expect(VoteCloseResponse(placed: 3).summary == "3 dagen gevuld.")
    }

    @Test func castBodyUsesSnakeCaseKey() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(VoteCastBody(week: "2026-10-19", recipeId: 3, on: false))) as? [String: Any]
        #expect(json?["recipe_id"] as? Int == 3 && json?["on"] as? Bool == false)
    }
}
