import Foundation

/// Wens-knop per dag, gelijk aan de chips op /plannen (backend/app/wishes.py `LABELS`).
enum WishChip: String, CaseIterable, Identifiable, Sendable {
    case rijst, pasta, aardappel, wraps, noedels, vis, vega, kip, snel, vriezer, vrij, overslaan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rijst: "Rijst"
        case .pasta: "Pasta"
        case .aardappel: "Aardappel"
        case .wraps: "Wraps"
        case .noedels: "Noedels"
        case .vis: "Vis"
        case .vega: "Vega"
        case .kip: "Kip"
        case .snel: "Snel klaar"
        case .vriezer: "Uit de vriezer"
        case .vrij: "Geen idee"
        case .overslaan: "Overslaan"
        }
    }

    /// Altijd zichtbaar (zoals op /plannen); de rest zit achter "Meer…".
    static let main: [WishChip] = [.rijst, .pasta, .aardappel, .wraps, .vriezer, .vrij]
    static let more: [WishChip] = [.noedels, .vis, .vega, .kip, .snel, .overslaan]

    var isMore: Bool { Self.more.contains(self) }

    /// Geen recept nodig (geen boodschappen voor deze dag).
    var isSpecial: Bool { self == .vriezer || self == .overslaan }
}
