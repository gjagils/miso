import Foundation
import Observation

/// Zoeken naar AH-producten (voor koppelen in een recept en in Ontbrekend).
@MainActor
@Observable
final class ProductSearchModel {
    var query: String
    private(set) var results: [AHProduct] = []
    private(set) var searching = false
    private(set) var errorText: String?
    /// Waar de huidige resultaten bij horen (voor "Niets gevonden voor ...").
    private(set) var searchedQuery = ""

    init(query: String) {
        self.query = query
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func search(api: API) async {
        let q = trimmedQuery
        guard !q.isEmpty else {
            results = []
            searchedQuery = ""
            return
        }
        guard q != searchedQuery || errorText != nil else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await api.searchProducts(q)
            guard q == trimmedQuery else { return } // intussen verder getypt
            results = found
            searchedQuery = q
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            errorText = error.localizedDescription
        }
    }
}
