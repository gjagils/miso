import Foundation

/// Uitkomst van het Inplannen-scherm.
enum PlanSheetResult {
    /// Opgeslagen (mode `.plan`).
    case saved(PlanCreateResponse)
    /// Gekozen maar niet opgeslagen (mode `.pick`).
    case picked(date: String, persons: Int, cookDouble: CookDouble?)
    /// Verplaatst (mode `.move`).
    case moved(PlanUpdateResponse)
}
