import Observation

/// Tabblad-keuze en verzoeken tussen tabbladen (bijv. "Plan volgende week" vanaf Vandaag).
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case today, kiezen, recipes, plan, more
    }

    var tab: Tab = .today
    /// Week (maandag) die "Wat eten we?" moet plannen; wordt leeggemaakt zodra Wat eten we? hem oppakt.
    var kiezenWeek: String?
    /// Telt op als een recept is bewerkt, gekoppeld of verwijderd; lijsten die recepten tonen laden dan opnieuw.
    private(set) var recipesVersion = 0
    /// Telt op als er buiten het weekmenu iets is ingepland (receptdetail, vriezer).
    private(set) var planVersion = 0

    func recipesChanged() {
        recipesVersion += 1
    }

    func planChanged() {
        planVersion += 1
    }

    /// Opent "Wat eten we?" voor een bepaalde week.
    func planWeek(_ week: String) {
        kiezenWeek = week
        tab = .kiezen
    }
}
