import Foundation
import Observation

/// "Zoek goedkopere producten" bij een recept: zoekt bij AH, laat een voorstel zien en koppelt de keuze.
@MainActor
@Observable
final class CheaperModel {
    private(set) var suggestions: [CheaperSuggestion] = []
    private(set) var totalSaving = 0.0
    private(set) var searching = false
    private(set) var searched = false
    private(set) var busyIndex: Int?
    var errorText: String?

    func search(recipeID: Int, api: API) async {
        searching = true
        errorText = nil
        defer { searching = false }
        do {
            let result = try await api.cheaper(recipeID: recipeID)
            guard result.ok else {
                errorText = result.error ?? "Zoeken is niet gelukt. Probeer het zo nog eens."
                return
            }
            suggestions = result.suggestions
            totalSaving = result.totalSaving
            searched = true
        } catch {
            errorText = "Zoeken is niet gelukt. \(error.localizedDescription)"
        }
    }

    /// Koppelt het goedkopere product (handmatig, dus Miso onthoudt het). Geeft terug of het gelukt is.
    func choose(_ suggestion: CheaperSuggestion, recipeID: Int, api: API) async -> Bool {
        busyIndex = suggestion.index
        defer { busyIndex = nil }
        do {
            _ = try await api.updateIngredient(recipeID: recipeID, index: suggestion.index,
                                               .choose(suggestion.alternative.product, text: suggestion.text))
            suggestions.removeAll { $0.index == suggestion.index }
            totalSaving = suggestions.reduce(0) { $0 + $1.saving }
            return true
        } catch {
            errorText = (error as? APIError)?.isConflict == true
                ? "Het recept is intussen gewijzigd. Zoek opnieuw."
                : error.localizedDescription
            return false
        }
    }
}
