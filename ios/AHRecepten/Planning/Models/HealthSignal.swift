import Foundation

/// Signaal uit de weekanalyse ("goed", "let_op", "tip").
struct HealthSignal: Decodable, Hashable, Sendable {
    let type: String
    let tekst: String
}
