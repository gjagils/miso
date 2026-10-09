import Foundation

extension WeekHealth {
    /// "5 avonden (1 restje) · gem. 620 kcal p.p. · 180 g groente p.p."
    var summary: String {
        guard dagen > 0 else { return "Nog niets gepland deze week." }
        var parts = ["\(dagen) \(dagen == 1 ? "avond" : "avonden")\(restjes > 0 ? " (\(plural(restjes, "restje", "restjes")))" : "")"]
        if let gemiddeldKcal { parts.append("gem. \(gemiddeldKcal) kcal p.p.") }
        if let groenteGPerDag { parts.append("\(groenteGPerDag) g groente p.p.") }
        if let schijfPct { parts.append("Schijf van Vijf \(schijfPct)%") }
        return parts.joined(separator: " · ")
    }
}
