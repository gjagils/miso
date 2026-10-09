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

    /// Opent "Wat eten we?" voor een bepaalde week.
    func planWeek(_ week: String) {
        kiezenWeek = week
        tab = .kiezen
    }
}
