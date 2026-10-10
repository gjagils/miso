import Foundation

/// Filterknoppen boven de receptenlijst (zoals op /recepten).
enum RecipeFilter: String, CaseIterable, Identifiable, Sendable {
    case all, favorites, byHeart, mealKits, archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .favorites: "♥ Favorieten"
        case .byHeart: "Uit mijn hoofd"
        case .mealKits: "Maaltijdpakketten"
        case .archived: "Opgeruimd"
        }
    }

    /// Waarde voor `GET /api/recipes?filter=`. Maaltijdpakketten filtert de app zelf uit "alles".
    var serverValue: String {
        switch self {
        case .all, .mealKits: ""
        case .favorites: "favorites"
        case .byHeart: "by_heart"
        case .archived: "archived"
        }
    }

    func apply(_ recipes: [RecipeSummary]) -> [RecipeSummary] {
        self == .mealKits ? recipes.filter(\.isMealKit) : recipes
    }

    var emptyTitle: String {
        switch self {
        case .all: "Nog geen recepten"
        case .favorites: "Nog geen favorieten"
        case .byHeart: "Nog niets uit je hoofd"
        case .mealKits: "Geen maaltijdpakketten"
        case .archived: "Niets opgeruimd"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Tik op + om je eerste recept toe te voegen."
        case .favorites: "Tik bij een recept op ♥ Favoriet; Miso stelt favorieten vaker voor."
        case .byHeart: "Recepten die je uit je hoofd kent, houden hun boodschappen maar slaan de kookmodus over."
        case .mealKits: "AH-maaltijdpakketten verschijnen hier vanzelf."
        case .archived: "Opgeruimde recepten kun je hier terugzetten."
        }
    }
}
