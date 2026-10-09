import Foundation

/// Zoekterm voor AH uit een ingrediëntregel: "2 gele paprika's (in reepjes)" -> "gele paprika's".
/// Haalt hoeveelheden, eenheden, tekst tussen haakjes en bereidingswijze na een komma weg.
enum IngredientSearchTerm {
    private static let units: Set<String> = [
        "g", "gr", "gram", "kg", "kilo", "mg", "ml", "cl", "dl", "l", "liter",
        "el", "tl", "eetlepel", "eetlepels", "theelepel", "theelepels", "lepel", "lepels",
        "stuk", "stuks", "teen", "teentje", "teentjes", "tenen", "blik", "blikje", "blikjes", "blikken",
        "pak", "pakje", "pakjes", "pakken", "zak", "zakje", "zakjes", "bos", "bosje", "bosjes",
        "snuf", "snufje", "snufjes", "handje", "handjes", "handvol", "takje", "takjes", "plak", "plakje",
        "plakjes", "plakken", "kop", "kopje", "kopjes", "mespunt", "mespuntje", "scheut", "scheutje",
        "potje", "pot", "fles", "flesje", "bakje", "bakjes", "doos", "doosje", "x",
    ]

    static func from(_ text: String) -> String {
        var line = text.lowercased()
        // Tekst tussen haakjes en alles na een komma ("ui, gesnipperd") weg.
        line = line.replacing(#/\([^)]*\)/#, with: " ")
        if let comma = line.firstIndex(of: ",") { line = String(line[..<comma]) }
        var words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, isAmount(first) || units.contains(first.trimmingCharacters(in: .punctuationCharacters)) {
            words.removeFirst()
        }
        let result = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return result.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    /// "2", "1/2", "½", "2-3", "1,5", "200g", "2x".
    private static func isAmount(_ word: String) -> Bool {
        word.wholeMatch(of: #/[0-9½¼¾⅓⅔.,\/\-–]+(g|gr|kg|ml|cl|dl|l|x)?/#) != nil
    }
}
