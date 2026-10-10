import Foundation

// Gezinsleden en wensen (backend/app/api/family.py). Er wordt nooit iets besteld.
extension API {
    func members() async throws -> MembersResponse {
        try await get("api/members")
    }

    func saveMembers(_ drafts: [MemberDraft]) async throws -> MembersSaveResponse {
        try await put("api/members", json: MembersSaveBody(members: drafts))
    }

    func familyWishes() async throws -> [FamilyWish] {
        let result: WishesResponse = try await get("api/wishes")
        return result.wishes
    }

    /// Wens doorgeven: een recept, een gerecht als tekst, of iets voor de boodschappen.
    func addWish(_ body: WishBody) async throws -> WishesResponse {
        try await post("api/wishes", json: body)
    }

    /// Wens afhandelen (✕ of na "Zet op deze dag").
    func wishDone(_ id: Int) async throws -> WishesResponse {
        try await post("api/wishes/\(id)/done", json: EmptyBody())
    }

    func deleteWish(_ id: Int) async throws -> WishesResponse {
        try await delete("api/wishes/\(id)")
    }

    /// Boodschappenwens op het AH-lijstje (alleen ouders). Bestelt niets.
    func wishToList(_ id: Int) async throws -> WishToListResponse {
        try await post("api/wishes/\(id)/to-list", json: EmptyBody())
    }
}
