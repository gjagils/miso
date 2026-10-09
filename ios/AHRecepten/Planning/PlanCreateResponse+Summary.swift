import Foundation

extension PlanCreateResponse {
    /// "Lasagne staat op maandag 12 okt (voor 6), de rest op dinsdag 13 okt." (zoals de web-versie)
    var summary: String {
        guard let first = entries.first else { return "Ingepland." }
        var text = "\(first.title) staat op \(KiezenDates.label(first.date).lowercased())"
        if first.kind != .stock && first.persons > 0 { text += " (voor \(first.persons))" }
        if let rest = entries.first(where: { $0.kind == .leftover && $0.sourceEntryId == first.entryId }) {
            text += ", de rest op \(KiezenDates.label(rest.date).lowercased())"
        }
        if let freezerItem, first.cookDouble == .freezer {
            text += ", \(plural(freezerItem.portions, "portie", "porties")) naar de vriezer"
        }
        return text + "."
    }
}
