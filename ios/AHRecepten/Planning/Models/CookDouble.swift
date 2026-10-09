import Foundation

/// "Kook dubbel": wat er met de tweede helft gebeurt.
enum CookDouble: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case tomorrow
    case freezer

    var id: String { rawValue }

    /// Tekst in de keuze "Wat doe je met de rest?".
    var choiceLabel: String {
        switch self {
        case .tomorrow: "morgen opeten"
        case .freezer: "naar de vriezer"
        }
    }

    /// Korte uitleg bij een ingeplande regel.
    var summary: String {
        switch self {
        case .tomorrow: "dubbel: morgen de rest"
        case .freezer: "dubbel: helft naar de vriezer"
        }
    }
}
