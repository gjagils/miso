import Foundation

/// Snel voorstel als er vandaag niets gepland is: een favoriet, iets uit de vriezer of iets snels.
struct TodaySuggestion: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case recipe(RecipeSummary)
        case freezer
    }

    let id: String
    let title: String
    let subtitle: String
    let kind: Kind

    /// Kies (stabiel per dag) een favoriet en een snel recept (≤ 30 min), plus de vriezer ertussen.
    /// `dayNumber` wisselt de keuze per dag, zodat het niet elke dag hetzelfde voorstel is.
    static func make(favorites: [RecipeSummary], all: [RecipeSummary], dayNumber: Int) -> [TodaySuggestion] {
        var out: [TodaySuggestion] = []
        let usable = { (r: RecipeSummary) in !(r.archived ?? false) }
        let favs = favorites.filter(usable)
        var favorite: RecipeSummary?
        if !favs.isEmpty {
            favorite = favs[abs(dayNumber) % favs.count]
            if let favorite {
                out.append(TodaySuggestion(id: "fav/\(favorite.id)", title: favorite.name,
                                           subtitle: ["♥ Favoriet", favorite.totalTime].filter { !$0.isEmpty }
                                               .joined(separator: " · "),
                                           kind: .recipe(favorite)))
            }
        }
        out.append(TodaySuggestion(id: "freezer", title: "Iets uit de vriezer",
                                   subtitle: "Geen boodschappen nodig", kind: .freezer))
        let quick = all.filter { usable($0) && $0.id != favorite?.id }
            .filter { (PlannenLogic.minutes($0.totalTime) ?? 999) <= 30 }
        if !quick.isEmpty {
            let pick = quick[abs(dayNumber) % quick.count]
            out.append(TodaySuggestion(id: "quick/\(pick.id)", title: pick.name,
                                       subtitle: ["Iets snels", pick.totalTime].filter { !$0.isEmpty }
                                           .joined(separator: " · "),
                                       kind: .recipe(pick)))
        }
        return out
    }
}
