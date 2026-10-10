import Foundation

/// Ingrediënten omrekenen voor het aantal personen, zoals `scale_line` en `recipe_servings` in
/// backend/app/planning.py: alleen het getal vooraan ("200 g", "1/2", "½", "2-3").
enum IngredientScaler {
    static let defaultServings = 4

    private static let amount = try! NSRegularExpression(
        pattern: #"^\s*(\d+/\d+|\d+(?:[.,]\d+)?(?:\s*-\s*\d+(?:[.,]\d+)?)?|[½¼¾])"#)
    private static let dash = try! NSRegularExpression(pattern: #"\s*-\s*"#)
    private static let fractions: [String: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75]

    /// "4 personen", "4", "4-6 pers." → 4; onbekend of onzinnig → 4.
    static func servings(_ text: String) -> Int {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression), let n = Int(text[range]),
              (1...50).contains(n) else { return defaultServings }
        return n
    }

    /// Factor voor `persons` personen bij een recept voor `servings` ("4 personen"). nil of 0 = niet omrekenen.
    static func factor(persons: Int?, servings: String) -> Double {
        guard let persons, persons > 0 else { return 1 }
        return Double(persons) / Double(Self.servings(servings))
    }

    static func needsScaling(_ factor: Double) -> Bool { abs(factor - 1) >= 0.01 }

    /// "200 g kipfilet" ×2 → "400 g kipfilet"; "1/2 ui" ×2 → "1 ui"; "2-3 tenen" ×2 → "4-6 tenen".
    static func scaleLine(_ text: String, factor: Double) -> String {
        guard needsScaling(factor) else { return text }
        let ns = text as NSString
        guard let m = amount.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
        let raw = ns.substring(with: m.range(at: 1))
        let parts: [String]
        if raw.contains("-") {
            let rns = raw as NSString
            parts = dash.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: rns.length),
                                                  withTemplate: "-").components(separatedBy: "-")
        } else {
            parts = [raw]
        }
        let scaled = parts.map { format(number($0) * factor) }.joined(separator: "-")
        return scaled + ns.substring(from: m.range.location + m.range.length)
    }

    private static func number(_ s: String) -> Double {
        let s = s.trimmingCharacters(in: .whitespaces)
        if let f = fractions[s] { return f }
        if s.contains("/") {
            let ab = s.split(separator: "/").compactMap { Double($0) }
            return ab.count == 2 && ab[1] != 0 ? ab[0] / ab[1] : 0
        }
        return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Zoals `fmt` op de server: heel getal, ½ ¼ ¾, anders één decimaal met komma.
    static func format(_ x: Double) -> String {
        if abs(x - x.rounded()) < 0.05 { return String(Int(x.rounded())) }
        let whole = Int(x)
        for (frac, sym) in [(0.5, "½"), (0.25, "¼"), (0.75, "¾")] where abs(x - Double(whole) - frac) < 0.05 {
            return (whole == 0 ? "" : String(whole)) + sym
        }
        return String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",")
    }
}
