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
}
