import Foundation

/// Opent het Inplannen-scherm (zoals `MisoPlan.open(...)` op de web-versie).
struct PlanSheetRequest: Identifiable {
    let id = UUID()
    var mode: PlanSheetMode = .plan
    /// Vast recept (geen zoeken).
    var recipe: PlanRecipeChoice?
    /// Tabbladen "Recept" en "Uit de vriezer / hebben we al", met zoeken.
    var showTabs = false
    var tab: PlanSheetTab = .recipe
    /// Voorgeselecteerd vriezer-item (opent op het voorraad-tabblad).
    var freezerItem: FreezerItem?
    /// Voorgeselecteerde dag.
    var date: String?
    /// Eerste dag van de 7 dagchips (default: vandaag).
    var start: String?
    /// Startwaarden; nil = huishoudgrootte / niet dubbel.
    var persons: Int?
    var cookDouble: CookDouble?
}
