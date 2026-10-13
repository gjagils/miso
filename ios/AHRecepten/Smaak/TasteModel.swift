import Foundation
import Observation

/// Smaak per persoon: laden, toevoegen, weghalen en voorgestelde afkeer bevestigen of wegwuiven.
@MainActor
@Observable
final class TasteModel {
    private(set) var members: [TasteMember] = []
    private(set) var suggestions: [TasteSuggestion] = []
    private(set) var loaded = false
    private(set) var busy = false
    var errorText: String?

    func load(api: API) async {
        apply(try? await api.tastes(), fallback: "Smaak ophalen mislukt.")
        loaded = true
    }

    func add(memberID: String, term: String, kind: TasteKind, api: API) async -> Bool {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else {
            errorText = "Geef een ingrediënt, bijvoorbeeld “paprika”."
            return false
        }
        return await run { try await api.addTaste(memberID: memberID, term: clean, kind: kind) }
    }

    func remove(_ preference: TastePreference, api: API) async {
        _ = await run { try await api.removeTaste(memberID: preference.memberId, id: preference.id) }
    }

    func confirm(_ suggestion: TasteSuggestion, api: API) async {
        _ = await run { try await api.addTaste(memberID: suggestion.memberId, term: suggestion.term, kind: .dislike) }
    }

    func dismiss(_ suggestion: TasteSuggestion, api: API) async {
        _ = await run { try await api.dismissTaste(memberID: suggestion.memberId, term: suggestion.term) }
    }

    private func run(_ call: () async throws -> TasteResponse) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let result = try await call()
            guard result.ok else {
                errorText = result.error ?? "Opslaan mislukt."
                return false
            }
            apply(result, fallback: nil)
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    private func apply(_ result: TasteResponse?, fallback: String?) {
        guard let result, result.ok else {
            if let fallback { errorText = fallback }
            return
        }
        members = result.members
        suggestions = result.suggestions
        errorText = nil
    }
}
