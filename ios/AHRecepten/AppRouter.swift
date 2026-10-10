import Observation

/// Tabblad-keuze en verzoeken tussen tabbladen (bijv. "Plan volgende week" vanaf Vandaag).
/// Tabs volgen docs/plan-gebruiksgemak.md: Vandaag · Plannen · Recepten · Weekmenu · Meer.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case today, plannen, recipes, plan, more
    }

    var tab: Tab = .today
    /// Week (maandag) die "Wat eten we?" (Zelf recepten kiezen) moet plannen; leeg zodra die hem oppakt.
    var kiezenWeek: String?
    /// Week die Plannen moet openen; leeg zodra Plannen hem oppakt.
    var plannenWeek: String?
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

    /// Opent Plannen voor een bepaalde week (een datum in die week mag ook).
    func planWeek(_ week: String) {
        plannenWeek = week
        tab = .plannen
    }
}
