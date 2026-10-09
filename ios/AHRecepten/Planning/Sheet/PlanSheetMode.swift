import Foundation

/// Wat het Inplannen-scherm doet met de keuze.
enum PlanSheetMode: Equatable {
    /// Opslaan via `POST /api/plan/entries`.
    case plan
    /// Alleen teruggeven (Wat eten we? stap 2 slaat later zelf op).
    case pick
    /// Bestaande regel verplaatsen (en personen aanpassen) via `PATCH`.
    case move(PlanItem)
}
