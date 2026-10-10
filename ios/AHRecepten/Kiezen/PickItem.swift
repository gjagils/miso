import Foundation

// "Wat eten we?": recepten kiezen -> inplannen -> boodschappen.
// Spiegelt backend/app/templates/kiezen.html (zelfde endpoints, payloads en samenvoeg-logica).
// Er wordt nooit een AH-bestelling geplaatst: alleen lijstje vullen en mandje vullen/leegmaken.

/// Gekozen recept: een eigen recept of een Allerhande-recept.
struct PickItem: Identifiable, Hashable {
    enum Kind: Hashable { case own, ah }
    /// "own:<id>" of "ah:<allerhande-id>". Uniek over beide soorten heen, dus ook het `id`.
    let key: String
    let kind: Kind
    /// Recept-id op de server (eigen recept) of Allerhande-id. Niet uniek over beide soorten heen.
    let recipeID: Int
    let name: String
    let imageUrl: String
    let meta: String
    var favorite = false
    /// AH-maaltijdpakket (label op de kaart).
    var mealKit = false

    var id: String { key }

    static func own(_ r: RecipeSummary) -> PickItem {
        PickItem(key: "own:\(r.id)", kind: .own, recipeID: r.id, name: r.name, imageUrl: r.imageUrl,
                 meta: [r.servings, r.totalTime].filter { !$0.isEmpty }.joined(separator: " · "),
                 favorite: r.isFavorite, mealKit: r.isMealKit)
    }

    static func allerhande(_ h: AHRecipeHit) -> PickItem {
        var meta = [h.time ?? "", h.servings].filter { !$0.isEmpty }.joined(separator: " · ")
        if h.saved { meta += meta.isEmpty ? "in je recepten" : " · in je recepten" }
        return PickItem(key: "ah:\(h.id)", kind: .ah, recipeID: h.id, name: h.title, imageUrl: h.imageUrl ?? "", meta: meta)
    }
}
