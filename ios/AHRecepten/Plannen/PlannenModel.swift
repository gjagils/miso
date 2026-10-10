import Foundation
import Observation

/// Plannen met wensen per dag: week kiezen, wensen invullen (knoppen of één zin), voorstel bekijken en
/// wisselen, en met één knop in het weekmenu + op het AH-lijstje zetten. Bestelt nooit iets.
@MainActor
@Observable
final class PlannenModel {
    enum Step: Equatable { case wishes, proposal }

    /// Uitkomst van "Zet in weekmenu en op mijn AH-lijstje".
    struct ApplyOutcome: Equatable {
        let success: Bool
        let message: String
    }

    /// Maandag van de week die je plant (leeg tot de standaardweek bekend is).
    private(set) var week = ""
    private(set) var days: [PlannenDay] = []
    var wishes: [String: WishInput] = [:]
    var sentence = ""
    var showWeekend = false
    private(set) var step: Step = .wishes
    private(set) var selection: ProposalSelection?

    private(set) var loading = false
    private(set) var loadError: String?
    private(set) var readingSentence = false
    private(set) var sentenceMessage: String?
    private(set) var proposing = false
    private(set) var proposeMessage: String?
    private(set) var applying = false
    private(set) var applyOutcome: ApplyOutcome?

    var weekdays: [PlannenDay] { days.filter { !$0.isWeekend } }
    var weekendDays: [PlannenDay] { days.filter(\.isWeekend) }
    var openDays: [PlannenDay] { days.filter(\.isOpen) }
    var collected: [String: String] { PlannenLogic.collect(wishes, days: days) }
    /// Aantal open doordeweekse dagen zonder wens (voor "Rest: geen idee").
    var emptyOpenWeekdays: Int {
        weekdays.filter { $0.isOpen && (wishes[$0.date]?.isEmpty ?? true) }.count
    }
    var weekTitle: String { week.isEmpty ? "" : "Week van \(KiezenDates.short(week))" }

    // MARK: Week

    /// Eerste keer: de standaardweek (zoals /plannen); `requested` komt van "Plan volgende week" elders.
    func start(api: API, requested: String? = nil) async {
        if let requested {
            await load(api: api, week: PlannenLogic.monday(of: requested))
            return
        }
        guard week.isEmpty else { return await reload(api: api) }
        let today = KiezenDates.today
        let thisMonday = PlannenLogic.monday(of: today)
        let taken = (try? await api.planEntries(start: thisMonday, days: 7))
            .map { Set($0.entries.map(\.date)) } ?? []
        await load(api: api, week: PlannenLogic.defaultWeek(today: today, takenDates: taken))
    }

    func reload(api: API) async {
        guard !week.isEmpty else { return await start(api: api) }
        await load(api: api, week: week, keepWishes: true)
    }

    func shiftWeek(by weeks: Int, api: API) async {
        guard !week.isEmpty else { return }
        await load(api: api, week: KiezenDates.add(week, 7 * weeks))
    }

    private func load(api: API, week newWeek: String, keepWishes: Bool = false) async {
        if newWeek != week || !keepWishes {
            wishes = [:]
            sentence = ""
            sentenceMessage = nil
            proposeMessage = nil
            selection = nil
            step = .wishes
            applyOutcome = nil
        }
        week = newWeek
        loading = true
        defer { loading = false }
        do {
            let result = try await api.planEntries(start: newWeek, days: 7)
            guard week == newWeek else { return } // intussen naar een andere week gegaan
            days = PlannenDay.week(monday: newWeek, today: KiezenDates.today, entries: result.entries)
            // Wensen voor dagen die intussen gepland zijn, vervallen.
            wishes = wishes.filter { date, _ in days.first { $0.date == date }?.isOpen ?? false }
            loadError = nil
        } catch {
            guard week == newWeek else { return }
            if days.isEmpty || days.first?.date != newWeek {
                days = PlannenDay.week(monday: newWeek, today: KiezenDates.today, entries: [])
            }
            loadError = error.localizedDescription
        }
    }

    // MARK: Wensen

    /// Wens van een dag als binding-vriendelijke subscript (`$model[wish: date]`).
    subscript(wish date: String) -> WishInput {
        get { wishes[date] ?? WishInput() }
        set { wishes[date] = newValue }
    }

    func toggle(_ chip: WishChip, on date: String) {
        var input = wishes[date] ?? WishInput()
        input.toggle(chip)
        wishes[date] = input
        proposeMessage = nil
    }

    func fillRestWithNoIdea() {
        PlannenLogic.fillEmptyWeekdays(&wishes, days: days)
        proposeMessage = nil
    }

    func clearWishes() {
        wishes = [:]
        sentenceMessage = nil
    }

    func readSentence(api: API) async {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !week.isEmpty else { return }
        readingSentence = true
        sentenceMessage = nil
        defer { readingSentence = false }
        do {
            let result = try await api.wishesFromText(week: week, text: text)
            guard result.ok else {
                sentenceMessage = result.error ?? "Miso snapte de zin niet. Kies per dag een knop."
                return
            }
            let filled = PlannenLogic.merge(result.wishes, into: &wishes, days: days)
            if filled.contains(where: { date in days.first { $0.date == date }?.isWeekend ?? false }) {
                showWeekend = true
            }
            sentenceMessage = filled.isEmpty
                ? "Miso vond geen open dagen in je zin. Kies per dag een knop."
                : "\(plural(filled.count, "dag", "dagen")) ingevuld. Pas aan waar nodig."
        } catch {
            sentenceMessage = error.localizedDescription
        }
    }

    // MARK: Voorstel

    func propose(api: API) async {
        let wanted = collected
        guard !wanted.isEmpty else {
            proposeMessage = "Kies voor minstens één dag een wens."
            return
        }
        proposing = true
        proposeMessage = nil
        defer { proposing = false }
        do {
            let result = try await api.propose(week: week, wishes: wanted)
            guard result.ok else {
                proposeMessage = "Voorstellen lukte niet. Probeer het nog eens."
                return
            }
            selection = ProposalSelection(days: result.days.sorted { $0.date < $1.date })
            applyOutcome = nil
            step = .proposal
        } catch {
            proposeMessage = "Voorstellen lukte niet. \(error.localizedDescription)"
        }
    }

    func choose(_ index: Int, for day: ProposalDay) {
        selection?.choose(index, for: day)
    }

    /// Terug naar de wensen ("Andere wensen"); de wensen blijven staan.
    func backToWishes() {
        step = .wishes
        applyOutcome = nil
    }

    /// Inplannen en daarna het AH-lijstje bijwerken (`POST /api/plan/apply` + `POST /api/plan/sync`).
    /// Geeft true als er iets is ingepland.
    func apply(api: API) async -> Bool {
        guard let selection, !applying else { return false }
        applying = true
        defer { applying = false }
        let response: PlanApplyResponse
        do {
            response = try await api.applyProposal(
                PlanApplyBody(week: week, choices: selection.choices, swapped: selection.swapped))
        } catch {
            applyOutcome = ApplyOutcome(success: false, message: "Inplannen lukte niet. \(error.localizedDescription)")
            return false
        }
        guard response.ok else {
            applyOutcome = ApplyOutcome(success: false, message: response.error ?? "Inplannen lukte niet.")
            return false
        }
        var text = "\(plural(response.added, "dag", "dagen")) ingepland."
        do {
            let sync = try await api.pushWeekToList(week)
            if sync.ok {
                let added = sync.added ?? 0
                text += added > 0 ? " \(plural(added, "product", "producten")) op je AH-lijstje gezet."
                                  : " Alles stond al op je AH-lijstje."
            } else {
                text += " Lijstje bijwerken lukte niet: \(sync.error ?? "onbekende fout")."
            }
        } catch {
            text += " Lijstje bijwerken lukte niet: \(error.localizedDescription)"
        }
        applyOutcome = ApplyOutcome(success: true, message: text)
        return response.added > 0
    }

    /// Na "Klaar": opnieuw beginnen met de (nu deels geplande) week.
    func finish(api: API) async {
        selection = nil
        step = .wishes
        applyOutcome = nil
        wishes = [:]
        sentence = ""
        sentenceMessage = nil
        await load(api: api, week: week, keepWishes: true)
    }
}
