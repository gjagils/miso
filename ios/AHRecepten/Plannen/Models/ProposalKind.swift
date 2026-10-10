import Foundation

/// Wat er voor een dag wordt voorgesteld. Onbekende waarden worden `.none` (niets voorstellen).
enum ProposalKind: String, Decodable, Sendable {
    case recipe, vriezer, overslaan, taken, none

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ProposalKind(rawValue: raw) ?? .none
    }
}
