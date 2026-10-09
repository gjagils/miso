import Foundation

/// Soort planregel. Onbekende waarden van de server worden `.other` (niet crashen op nieuwe soorten).
enum PlanKind: String, Decodable, Hashable, Sendable {
    /// Recept koken.
    case recipe
    /// "Rest van …" (meestal door "kook dubbel, morgen opeten").
    case leftover
    /// "Uit de vriezer / hebben we al": vrije tekst + extra's.
    case stock
    case other

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = PlanKind(rawValue: raw) ?? .other
    }
}
