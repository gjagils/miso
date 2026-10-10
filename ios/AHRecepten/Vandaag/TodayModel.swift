import Foundation
import Observation

/// Vandaag als kook-startscherm: wat staat er vandaag, morgen en overmorgen; niets gepland = drie voorstellen.
@MainActor
@Observable
final class TodayModel {
    private(set) var today = KiezenDates.today
    private(set) var entries: [PlanItem] = []
    /// Volledig recept van vandaag (voor "Start met koken" en "uit mijn hoofd").
    private(set) var todayRecipe: RecipeDetail?
    private(set) var suggestions: [TodaySuggestion] = []
    private(set) var loaded = false
    private(set) var errorText: String?
    private(set) var planningSuggestion: String?

    var todayItems: [PlanItem] { entries.filter { $0.date == today } }
    /// Eerste recept van vandaag (koken), anders nil.
    var mainItem: PlanItem? { todayItems.first { $0.kind == .recipe && $0.recipeId != nil } ?? todayItems.first }
    var otherTodayItems: [PlanItem] { todayItems.filter { $0.id != mainItem?.id } }

    /// Morgen en overmorgen.
    var upcoming: [(date: String, items: [PlanItem])] {
        (1...2).map { offset in
            let date = KiezenDates.add(today, offset)
            return (date, entries.filter { $0.date == date })
        }
    }

    func load(api: API) async {
        today = KiezenDates.today
        do {
            let result = try await api.planEntries(start: today, days: 3)
            entries = result.entries
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
        loaded = true
        if mainItem?.kind == .recipe, mainItem?.recipeId != nil {
            if todayRecipe?.id != mainItem?.recipeId { todayRecipe = nil }
            _ = await loadTodayRecipe(api: api)
        } else {
            todayRecipe = nil
        }
        if todayItems.isEmpty && errorText == nil {
            await loadSuggestions(api: api)
        } else {
            suggestions = []
        }
    }

    /// Volledig recept van vandaag ophalen (ook opnieuw als het eerder mislukte, bijv. bij "Start met koken").
    func loadTodayRecipe(api: API) async -> RecipeDetail? {
        guard let id = mainItem?.recipeId, mainItem?.kind == .recipe else { return nil }
        if let fresh = try? await api.recipe(id: id) { todayRecipe = fresh }
        return todayRecipe
    }

    private func loadSuggestions(api: API) async {
        async let favorites = try? api.recipes(filter: .favorites)
        async let all = try? api.recipes(filter: .all)
        let dayNumber = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        suggestions = TodaySuggestion.make(favorites: await favorites ?? [], all: await all ?? [], dayNumber: dayNumber)
    }

    /// Voorstel voor vandaag inplannen. Geeft true als het gelukt is.
    func plan(_ suggestion: TodaySuggestion, api: API) async -> Bool {
        planningSuggestion = suggestion.id
        defer { planningSuggestion = nil }
        let body: PlanEntryCreateBody
        switch suggestion.kind {
        case .recipe(let recipe):
            body = .recipe(recipe.id, date: today, persons: nil, cookDouble: nil)
        case .freezer:
            body = .stock(date: today, text: "Iets uit de vriezer", extras: [], freezerItemId: nil)
        }
        do {
            _ = try await api.createPlanEntry(body)
            await load(api: api)
            return true
        } catch {
            errorText = "Inplannen lukte niet. \(error.localizedDescription)"
            return false
        }
    }

    func report(_ message: String) {
        errorText = message
    }

    func dismissError() {
        errorText = nil
    }
}
