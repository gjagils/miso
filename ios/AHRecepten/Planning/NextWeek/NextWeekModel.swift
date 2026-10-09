import Foundation
import Observation

/// Banner "Volgende week" op Vandaag: status, voorstel van Miso en het voorstel overnemen.
@MainActor
@Observable
final class NextWeekModel {
    private(set) var status: NextWeekStatus?
    private(set) var suggestions: [MenuSuggestion]?
    private(set) var suggesting = false
    private(set) var applying = false
    private(set) var message: String?

    /// Groot tonen: vanaf 2 dagen voor de besteldag, zolang de week niet compleet is.
    var isProminent: Bool { (status?.prominent ?? false) && !(status?.isComplete ?? true) }

    /// Status ophalen en daarmee de lokale herinnering bijwerken. Een oudere server zonder dit endpoint: geen banner.
    func load(api: API) async {
        guard let result = try? await api.nextWeekStatus() else { return }
        // Een voorstel hoort bij de lege dagen van dat moment; is er intussen iets gepland, dan vervalt het.
        if result.week != status?.week || result.plannedDays != status?.plannedDays { suggestions = nil }
        status = result
        await OrderReminderScheduler.apply(result)
    }

    func suggest(api: API) async {
        guard let week = status?.week else { return }
        suggesting = true
        message = nil
        defer { suggesting = false }
        do {
            let result = try await api.suggestWeek(week)
            suggestions = result.voorstel
            if result.voorstel.isEmpty {
                message = result.zonderProfiel > 0
                    ? "Miso kent je recepten nog niet goed genoeg; probeer het zo nog eens."
                    : "Geen voorstel: alle dagen zijn al bezet."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Voorstel overnemen: per dag `POST /api/plan/entries` (huishoudgrootte).
    func apply(api: API) async -> Bool {
        guard let suggestions, !suggestions.isEmpty else { return false }
        applying = true
        defer { applying = false }
        var failed = 0
        for item in suggestions {
            do {
                _ = try await api.createPlanEntry(.recipe(item.recipeId, date: item.date, persons: nil, cookDouble: nil))
            } catch {
                failed += 1
            }
        }
        self.suggestions = nil
        message = failed == 0 ? "Toegevoegd aan het weekmenu van volgende week."
                              : "\(plural(failed, "dag", "dagen")) niet gelukt. Probeer het nog eens."
        await load(api: api)
        return failed == 0
    }

    func dismissSuggestions() {
        suggestions = nil
    }
}
