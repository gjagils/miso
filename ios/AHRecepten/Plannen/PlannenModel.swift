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
        /// Ingrediënten zonder AH-product (`status.unmatched`): link naar Ontbrekend.
        var unmatched = 0
        /// Het AH-lijstje bijwerken lukte niet (vaak: AH nog niet gekoppeld).
        var listFailed = false
    }

    /// Maandag van de week die je plant (leeg tot de standaardweek bekend is).
    private(set) var week = ""
    private(set) var days: [PlannenDay] = []
    var wishes: [String: WishInput] = [:] {
        didSet { if proposeMessage != nil && oldValue != wishes { proposeMessage = nil } }
    }
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
    /// Dag die nu wordt leeggemaakt (Haal weg).
    private(set) var clearingDate: String?
    /// "Wijzig": deze dagen kies je opnieuw; het oude gaat pas weg bij "Zet in weekmenu".
    private(set) var replacingDates: Set<String> = []
    /// Wensen van het gezin (bovenaan Plannen).
    private(set) var familyWishes: [FamilyWish] = []
    /// Wens waar nu iets mee gebeurt.
    private(set) var busyWishID: Int?
    /// Uitkomst van "Zet op deze dag" / "Op AH-lijstje".
    private(set) var wishMessage: String?
    /// recept-id → initialen van wie het een favoriet vindt (voor de voorstellen).
    private(set) var fans: [Int: [String]] = [:]

    var weekdays: [PlannenDay] { days.filter { !$0.isWeekend } }
    var weekendDays: [PlannenDay] { days.filter(\.isWeekend) }
    var openDays: [PlannenDay] { days.filter(\.isOpen) }
    var collected: [String: String] { PlannenLogic.collect(wishes, days: days) }
    /// Aantal open doordeweekse dagen zonder wens (voor "Rest: geen idee").
    var emptyOpenWeekdays: Int {
        weekdays.filter { $0.isOpen && (wishes[$0.date]?.isEmpty ?? true) }.count
    }
    /// Dagen waarop een wens van het gezin gezet kan worden: open (ook weekend), niet voorbij.
    var wishTargetDays: [PlannenDay] { days.filter { $0.taken.isEmpty && !$0.isPast } }
    /// Ma-vr staan er allemaal in (of zijn voorbij): niets meer voor te stellen doordeweeks.
    var weekdaysDone: Bool { !days.isEmpty && !weekdays.contains(where: \.isOpen) }
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
            replacingDates = []
        }
        week = newWeek
        loading = true
        defer { loading = false }
        do {
            let result = try await api.planEntries(start: newWeek, days: 7)
            guard week == newWeek else { return } // intussen naar een andere week gegaan
            days = PlannenDay.week(monday: newWeek, today: KiezenDates.today, entries: result.entries)
            markReplacing()
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

    /// Dagen die je via "Wijzig" opnieuw kiest, openzetten (alleen als er nog iets staat).
    private func markReplacing() {
        replacingDates = replacingDates.filter { date in days.contains { $0.date == date && $0.canChange } }
        for index in days.indices { days[index].replacing = replacingDates.contains(days[index].date) }
    }

    /// Wijzig: de dag opnieuw kiezen (er wordt nog niets gewist). Nog eens = "Toch houden".
    func toggleReplace(_ day: PlannenDay) {
        if replacingDates.contains(day.date) {
            replacingDates.remove(day.date)
            wishes[day.date] = nil
        } else {
            replacingDates.insert(day.date)
        }
        markReplacing()
    }

    /// Vanaf Vandaag ("Iets snellers"): week van die dag, dag opnieuw kiezen met de wens, en voorstellen.
    func handle(_ request: PlannenRequest, api: API) async {
        let monday = PlannenLogic.monday(of: request.date)
        if monday != week { await load(api: api, week: monday) } else { await load(api: api, week: week, keepWishes: true) }
        guard let day = days.first(where: { $0.date == request.date }), !day.isPast else { return }
        if day.canChange { replacingDates.insert(day.date); markReplacing() }
        wishes[day.date] = WishInput(chip: request.wish)
        if day.isWeekend { showWeekend = true }
        selection = nil
        step = .wishes
        await propose(api: api, only: [day.date])
    }

    // MARK: Wensen van het gezin

    func loadFamily(api: API) async {
        if let list = try? await api.familyWishes() { familyWishes = FamilyWish.groceriesFirst(list) }
        if let recipes = try? await api.recipes() {
            fans = Dictionary(recipes.compactMap { r in r.fans.map { (r.id, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// "Zet op deze dag": recept meteen inplannen; tekst wordt de wens van die dag. Geeft true als er iets
    /// is ingepland.
    func place(_ wish: FamilyWish, on date: String, api: API) async -> Bool {
        busyWishID = wish.id
        defer { busyWishID = nil }
        wishMessage = nil
        if let recipeID = wish.recipeId {
            do {
                let result = try await api.applyProposal(
                    PlanApplyBody(week: week, choices: [.recipe(id: recipeID, date: date)], swapped: []))
                guard result.ok, result.added > 0 else {
                    wishMessage = result.error ?? "Inplannen lukte niet; staat er al iets op \(KiezenDates.label(date))?"
                    return false
                }
                await markDone(wish, api: api)
                wishMessage = "\(wish.what) staat op \(KiezenDates.label(date))."
                await load(api: api, week: week, keepWishes: true)
                return true
            } catch {
                wishMessage = error.localizedDescription
                return false
            }
        }
        wishes[date] = WishInput(serverValue: wish.what)
        if days.first(where: { $0.date == date })?.isWeekend == true { showWeekend = true }
        await markDone(wish, api: api)
        wishMessage = "“\(wish.what)” is de wens voor \(KiezenDates.label(date)). Tik op Stel recepten voor."
        return false
    }

    /// ✕: wens afhandelen.
    func markDone(_ wish: FamilyWish, api: API) async {
        do {
            let result = try await api.wishDone(wish.id)
            familyWishes = FamilyWish.groceriesFirst(result.wishes)
        } catch {
            familyWishes.removeAll { $0.id == wish.id }
        }
    }

    /// "Op AH-lijstje" voor een boodschappenwens. Geeft een link terug als AH niet gekoppeld is (ah.nl zet
    /// het dan op je lijstje). Bestelt nooit iets.
    func toList(_ wish: FamilyWish, api: API) async -> URL? {
        busyWishID = wish.id
        defer { busyWishID = nil }
        wishMessage = nil
        do {
            let result = try await api.wishToList(wish.id)
            guard result.ok else {
                wishMessage = result.error ?? "Op het lijstje zetten lukte niet."
                return nil
            }
            if let wishes = result.wishes { familyWishes = FamilyWish.groceriesFirst(wishes) }
            if let link = result.url, let url = URL(string: link) {
                wishMessage = "AH is nog niet gekoppeld: ah.nl opent om \(result.product ?? wish.what) op je lijstje te zetten."
                return url
            }
            wishMessage = "\(result.product ?? wish.what) staat op je AH-lijstje ✓"
            return nil
        } catch {
            wishMessage = error.localizedDescription
            return nil
        }
    }

    func dismissWishMessage() {
        wishMessage = nil
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

    /// Haal weg: alle planregels van die dag weghalen, daarna is de dag weer open.
    func clear(_ day: PlannenDay, api: API) async -> Bool {
        clearingDate = day.date
        defer { clearingDate = nil }
        do {
            for id in day.entryIDs {
                _ = try await api.deletePlanEntry(id)
            }
            await load(api: api, week: week, keepWishes: true)
            return true
        } catch {
            await load(api: api, week: week, keepWishes: true)
            loadError = "Leegmaken lukte niet. \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Voorstel

    func propose(api: API, only: [String]? = nil) async {
        var wanted = collected
        if let only { wanted = wanted.filter { only.contains($0.key) } }
        guard !wanted.isEmpty else {
            proposeMessage = "Kies voor minstens één dag een wens."
            return
        }
        proposing = true
        proposeMessage = nil
        defer { proposing = false }
        do {
            let replace = replacingDates.filter { wanted.keys.contains($0) }
            let result = try await api.propose(week: week, wishes: wanted, replace: replace.sorted())
            guard result.ok else {
                proposeMessage = "Voorstellen lukte niet. Probeer het nog eens."
                return
            }
            selection = ProposalSelection(days: result.days.sorted { $0.date < $1.date }, replacing: replace)
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
    /// `syncList: false` als AH niet gekoppeld is: dan alleen inplannen.
    func apply(api: API, syncList: Bool = true) async -> Bool {
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
        if !response.skipped.isEmpty {
            text += " Niet gelukt: \(response.skipped.map(KiezenDates.label).joined(separator: ", "))."
        }
        var unmatched = response.status?.unmatched.count ?? 0
        var listFailed = false
        replacingDates.subtract(selection.replacing)
        guard syncList else {
            text += " Koppel AH bij Meer, dan zet Miso de boodschappen ook op je lijstje."
            applyOutcome = ApplyOutcome(success: true, message: text, unmatched: unmatched, listFailed: false)
            return response.added > 0
        }
        do {
            let sync = try await api.pushWeekToList(week)
            if let status = sync.status { unmatched = status.unmatched.count }
            if sync.ok {
                let added = sync.added ?? 0
                text += added > 0 ? " \(plural(added, "product", "producten")) op je AH-lijstje gezet."
                                  : " Alles stond al op je AH-lijstje."
            } else {
                listFailed = true
                text += " Lijstje bijwerken lukte niet: \(sync.error ?? "onbekende fout")."
            }
        } catch {
            listFailed = true
            text += " Lijstje bijwerken lukte niet: \(error.localizedDescription)"
        }
        applyOutcome = ApplyOutcome(success: true, message: text, unmatched: unmatched, listFailed: listFailed)
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
