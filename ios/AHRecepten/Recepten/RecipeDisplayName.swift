import Foundation

/// Korte naam voor AH-maaltijdpakketten, zoals `display_name` op de server (backend/app/wishes.py):
/// "AH gesneden verspakket 'Indonesische' nasi goreng" → "Indonesische nasi goreng" (+ label Maaltijdpakket).
enum RecipeDisplayName {
    private static let packPrefix = try! NSRegularExpression(
        pattern: #"^ah\s+(excellent\s+|biologisch\s+)?(gesneden\s+)?verspakket\s+"#, options: [.caseInsensitive])
    private static let quoted = try! NSRegularExpression(pattern: #"(^|\s)['"]([^'"]+)['"]"#)

    static func short(_ name: String) -> String {
        var s = name
        s = packPrefix.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        s = quoted.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1$2")
        s = s.trimmingCharacters(in: .whitespaces)
        guard let first = s.first else { return name }
        return first.uppercased() + s.dropFirst()
    }

    /// Naam begint met "AH … verspakket": dit is een maaltijdpakket, ook als de collectie onbekend is.
    static func isPack(_ name: String) -> Bool {
        packPrefix.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}

extension RecipeSummary {
    var displayName: String { RecipeDisplayName.short(name) }
    var showsMealKitTag: Bool { isMealKit || RecipeDisplayName.isPack(name) }
    /// Initialen van wie het een favoriet vindt ("H S").
    var fansText: String { (fans ?? []).joined(separator: " ") }
}

extension RecipeDetail {
    var displayName: String { RecipeDisplayName.short(name) }
    var showsMealKitTag: Bool { isMealKit || RecipeDisplayName.isPack(name) }
}
