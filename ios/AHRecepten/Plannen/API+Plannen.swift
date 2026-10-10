import Foundation

// Plannen met wensen per dag (zelfde endpoints als backend/app/templates/plannen.html).
// Er wordt nooit iets besteld: alleen inplannen en het AH-lijstje bijwerken.
extension API {
    func propose(week: String, wishes: [String: String], replace: [String] = []) async throws -> ProposeResponse {
        try await post("api/plan/propose", json: ProposeBody(week: week, wishes: wishes, replace: replace))
    }

    /// Eén zin ("maandag rijst, dinsdag wraps") naar wensen per datum. Kan 502 geven als Claude het niet snapt.
    func wishesFromText(week: String, text: String) async throws -> WishesTextResponse {
        try await post("api/plan/wishes-text", json: WishesTextBody(week: week, text: text))
    }

    func applyProposal(_ body: PlanApplyBody) async throws -> PlanApplyResponse {
        try await post("api/plan/apply", json: body)
    }
}
