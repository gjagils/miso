import Foundation

/// Verzoek aan Plannen: deze dag opnieuw kiezen met deze wens (bijv. "Iets snellers" vanaf Vandaag).
struct PlannenRequest: Equatable, Sendable {
    let date: String
    let wish: WishChip
}
