import Foundation

/// Week-check onder het voorstel, zoals `weekCheck()` op /plannen:
/// "2× vega · 1× vis · 3× vlees/kip · 3 keukens · geen dubbelingen ✅".
enum WeekCheck {
    static func line(picks: [ProposalOption], freezerDays: Int) -> String {
        func count(_ k: String) -> Int { picks.filter { $0.eiwit == k }.count }
        let kitchens = Set(picks.map(\.keuken).filter { !$0.isEmpty }).count
        let names = picks.map { $0.name.lowercased() }
        let dupes = names.count - Set(names).count
        var parts = ["\(count("vega"))× vega", "\(count("vis"))× vis", "\(count("vlees") + count("kip"))× vlees/kip"]
        if kitchens > 0 { parts.append("\(kitchens) \(kitchens == 1 ? "keuken" : "keukens")") }
        if freezerDays > 0 { parts.append("\(freezerDays)× vriezer") }
        parts.append(dupes > 0 ? "⚠️ \(dupes) dubbel" : "geen dubbelingen ✅")
        return parts.joined(separator: " · ")
    }
}
