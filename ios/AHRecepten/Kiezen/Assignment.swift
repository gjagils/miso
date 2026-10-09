import Foundation

/// Gekozen eigen recept met de dag waarop het ingepland wordt.
struct Assignment: Identifiable {
    var id: Int { recipeId }
    let recipeId: Int
    let name: String
    let imageUrl: String
    /// "YYYY-MM-DD", of "" = niet inplannen
    var day: String
    /// Dag waarop het recept deze week al staat.
    var already: String?
    /// Voor hoeveel personen (default: huishoudgrootte).
    var persons: Int
    /// "Kook dubbel": morgen opeten of naar de vriezer.
    var cookDouble: CookDouble?

    /// Personen voor de boodschappen (dubbel koken = 2× zoveel), zoals `personsMap` op de web-versie.
    var groceryPersons: Int { persons * (cookDouble == nil ? 1 : 2) }
}
