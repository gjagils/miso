import Foundation

/// Open ingrediënten met dezelfde zoekterm over alle recepten ("2 gele paprika's" en "1 gele paprika").
struct MissingGroup: Decodable, Identifiable, Hashable, Sendable {
    var id: String { term }
    let term: String
    let lines: [MissingLine]

    /// Unieke receptnamen, in volgorde.
    var recipeNames: [String] {
        var seen = Set<String>()
        return lines.map(\.recipe).filter { seen.insert($0).inserted }
    }
}
