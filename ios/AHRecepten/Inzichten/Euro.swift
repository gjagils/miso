import Foundation

/// Bedragen in het Nederlands: "€ 12,50". Een eigen helper zodat alle schermen hetzelfde tonen.
enum Euro {
    static func format(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(Locale(identifier: "nl_NL")))
    }

    /// "−€ 2,80" voor voordeel (altijd positief meegeven).
    static func saving(_ value: Double) -> String { "−" + format(value) }
}
