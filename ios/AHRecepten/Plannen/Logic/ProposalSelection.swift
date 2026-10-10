import Foundation

/// Voorstel met de keuze per dag (index in `options`; 0 = Miso's eerste keuze).
struct ProposalSelection: Equatable, Sendable {
    let days: [ProposalDay]
    private(set) var picks: [String: Int] = [:]

    init(days: [ProposalDay]) {
        self.days = days
    }

    func pick(for day: ProposalDay) -> Int {
        let index = picks[day.date] ?? 0
        return day.options.indices.contains(index) ? index : 0
    }

    func chosen(for day: ProposalDay) -> ProposalOption? {
        day.kind == .recipe && !day.options.isEmpty ? day.options[pick(for: day)] : nil
    }

    /// Alternatieven: alle opties behalve de gekozen, met hun index.
    func alternatives(for day: ProposalDay) -> [(index: Int, option: ProposalOption)] {
        guard day.kind == .recipe else { return [] }
        let current = pick(for: day)
        return day.options.enumerated().filter { $0.offset != current }.map { ($0.offset, $0.element) }
    }

    mutating func choose(_ index: Int, for day: ProposalDay) {
        guard day.options.indices.contains(index) else { return }
        picks[day.date] = index
    }

    /// Wat naar `POST /api/plan/apply` gaat: recepten en vriezerdagen. Overslaan/bezet/niets gaat niet mee.
    var choices: [PlanApplyChoice] {
        days.compactMap { day in
            switch day.kind {
            case .vriezer: .freezer(date: day.date)
            case .recipe: chosen(for: day).map { .recipe($0, date: day.date) }
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
