import Foundation

/// Voorstel met de keuze per dag (index in `options`; 0 = Miso's eerste keuze).
struct ProposalSelection: Equatable, Sendable {
    let days: [ProposalDay]
    private(set) var picks: [String: Int] = [:]
    /// Dagen die via "Wijzig" opnieuw gekozen worden: bij bevestigen vervangt het nieuwe het oude.
    let replacing: Set<String>

    init(days: [ProposalDay], replacing: Set<String> = []) {
        self.days = days
        self.replacing = replacing
    }

    func pick(for day: ProposalDay) -> Int {
        let index = picks[day.date] ?? 0
        return day.options.indices.contains(index) ? index : 0
    }

    func chosen(for day: ProposalDay) -> ProposalOption? {
        day.kind == .recipe && !day.options.isEmpty ? day.options[pick(for: day)] : nil
    }

    /// Alternatieven: alle opties behalve de gekozen, en niets wat al op een andere dag gekozen is
    /// (nooit twee keer hetzelfde gerecht in een week).
    func alternatives(for day: ProposalDay) -> [(index: Int, option: ProposalOption)] {
        guard day.kind == .recipe else { return [] }
        let current = pick(for: day)
        let elsewhere = Set(days.filter { $0.date != day.date }.compactMap { chosen(for: $0)?.name.lowercased() })
        return day.options.enumerated()
            .filter { $0.offset != current && !elsewhere.contains($0.element.name.lowercased()) }
            .map { ($0.offset, $0.element) }
    }

    /// "2× vega · 1× vis · 3× vlees/kip · 3 keukens · geen dubbelingen ✅"
    var weekCheck: String {
        WeekCheck.line(picks: days.compactMap { chosen(for: $0) },
                       freezerDays: days.filter { $0.kind == .vriezer }.count)
    }

    mutating func choose(_ index: Int, for day: ProposalDay) {
        guard day.options.indices.contains(index) else { return }
        picks[day.date] = index
    }

    /// Wat naar `POST /api/plan/apply` gaat: recepten en vriezerdagen. Overslaan/bezet/niets gaat niet mee.
    var choices: [PlanApplyChoice] {
        days.compactMap { day in
            switch day.kind {
            case .vriezer: .freezer(date: day.date, replace: replacing.contains(day.date))
            case .recipe: chosen(for: day).map { .recipe($0, date: day.date, replace: replacing.contains(day.date)) }
            case .overslaan, .taken, .none: nil
            }
        }
    }

    /// Eigen recepten die Miso eerst voorstelde en die je wegwisselde.
    var swapped: [Int] {
        days.compactMap { day in
            guard day.kind == .recipe, pick(for: day) != 0 else { return nil }
            return day.options.first?.recipeId
        }
    }

    /// Aantal dagen dat in het weekmenu komt.
    var plannedCount: Int { choices.count }
}
