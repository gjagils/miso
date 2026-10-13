import Foundation

// Smaak per persoon (docs/plan-api.md): voorkeuren, afkeer en voorgestelde afkeer uit 👎.
extension API {
    func tastes() async throws -> TasteResponse {
        try await get("api/preferences")
    }

    func addTaste(memberID: String, term: String, kind: TasteKind) async throws -> TasteResponse {
        try await post("api/members/\(Self.pathSegment(memberID))/preferences", json: TasteBody(term: term, kind: kind.rawValue))
    }

    func removeTaste(memberID: String, id: Int) async throws -> TasteResponse {
        try await delete("api/members/\(Self.pathSegment(memberID))/preferences/\(id)")
    }

    func dismissTaste(memberID: String, term: String) async throws -> TasteResponse {
        try await post("api/preferences/dismiss", json: TasteDismissBody(memberId: memberID, term: term))
    }

    private static func pathSegment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
