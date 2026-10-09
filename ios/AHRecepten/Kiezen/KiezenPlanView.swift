import SwiftUI

// MARK: - Stap 2: inplannen

struct KiezenPlanView: View {
    @Environment(Session.self) private var session
    @Environment(KiezenModel.self) private var model
    let onNext: () -> Void

    @State private var dates: [String] = []
    @State private var weekPlan: [String: [PlanItem]] = [:]
    @State private var household = 4
    @State private var assign: [Assignment] = []
    /// Al opgeslagen recepten (bij opnieuw proberen na een fout niet dubbel opslaan).
    @State private var savedIDs: Set<Int> = []
    @State private var planRequest: PlanSheetRequest?
    /// Recept waarvoor het Inplannen-scherm (kook dubbel) open staat.
    @State private var editingRecipeID: Int?
    @State private var loading = false
    @State private var loaded = false
    @State private var saving = false
    /// Weekmenu ophalen mislukt (zonder iets om te tonen: foutscherm, anders melding erboven).
    @State private var loadError: String?
    /// Opslaan mislukt: de lijst en de gekozen dagen blijven staan, zodat je opnieuw kunt proberen.
    @State private var saveError: String?

    private let today = KiezenDates.today
    private var hasDays: Bool { assign.contains { !$0.day.isEmpty } }

    var body: some View {
        List {
            Section {
                HStack {
                    Button(action: previousWeek) {
                        Label("Vorige week", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    Spacer()
                    Text(model.week.isEmpty ? "Week" : "Week van \(KiezenDates.short(model.week))")
                        .font(.misoHeadline).foregroundStyle(Color.misoBlue)
                    Spacer()
                    Button(action: nextWeek) {
                        Label("Volgende week", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.week.isEmpty || loading || saving)
                .misoRow()
            } footer: {
                Text("Miso zet je keuze op de eerste vrije dagen. Kies zelf een andere dag als dat beter past.")
            }

            if let message = saveError ?? (dates.isEmpty ? nil : loadError) {
                ErrorBanner(message: message, onDismiss: dismissErrors)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if dates.isEmpty, let loadError {
                ErrorStateView(message: loadError).listRowBackground(Color.clear)
            } else if loading && dates.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else {
                ForEach(dates, id: \.self) { day in
                    let existing = weekPlan[day] ?? []
                    let mine = assign.filter { $0.day == day }
                    if !(day < today && existing.isEmpty && mine.isEmpty) {
                        Section {
                            ForEach(existing) { item in
                                KiezenExistingRow(item: item)
                            }
                            ForEach(mine) { a in assignRow(a) }
                            if existing.isEmpty && mine.isEmpty {
                                Text("Nog niets").foregroundStyle(.secondary)
                            }
                        } header: {
                            HStack {
                                Text(KiezenDates.label(day)).misoSectionHeader()
                                if day == today { Text("vandaag").misoChip(.misoOrange) }
                            }
                        }
                        .misoRow()
                    }
                }
                let loose = assign.filter { $0.day.isEmpty }
                if !loose.isEmpty {
                    Section {
                        ForEach(loose) { a in assignRow(a) }
                    } header: {
                        Text("Niet (opnieuw) inplannen").misoSectionHeader()
                    } footer: {
                        Text("Komen wel in je boodschappen bij de volgende stap.")
                    }
                    .misoRow()
                }
            }
        }
        .misoScreen()
        .navigationTitle("Inplannen")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            KiezenBar(title: hasDays ? (saveError == nil ? "Opslaan en verder" : "Opnieuw opslaan") : "Verder naar boodschappen",
                      enabled: loaded && !assign.isEmpty, busy: saving, action: startSave) {
                EmptyView()
            }
        }
        .task {
            if !loaded { await load(model.week.isEmpty ? nil : model.week) }
        }
        .sheet(item: $planRequest) { request in
            PlanSheet(request: request, onDone: picked)
        }
    }

    private func assignRow(_ a: Assignment) -> some View {
        KiezenAssignRow(assignment: a, dates: dates, day: dayBinding(a.recipeId),
                        onPersons: { setPersons($0, for: a.recipeId) },
                        onMore: { openOptions(a) })
    }

    /// Binding per rij: `assign` is een array van structs zonder vaste index, dus zoeken op recept-id.
    private func dayBinding(_ recipeId: Int) -> Binding<String> {
        Binding(
            get: { assign.first { $0.recipeId == recipeId }?.day ?? "" },
            set: { value in
                if let i = assign.firstIndex(where: { $0.recipeId == recipeId }) {
                    withAnimation { assign[i].day = value }
                }
            }
        )
    }

    // MARK: Acties

    private func setPersons(_ value: Int, for recipeId: Int) {
        if let i = assign.firstIndex(where: { $0.recipeId == recipeId }) { assign[i].persons = value }
    }

    /// "Kook dubbel…": het Inplannen-scherm in kies-modus (opslaan gebeurt bij "Opslaan en verder").
    private func openOptions(_ a: Assignment) {
        editingRecipeID = a.recipeId
        planRequest = PlanSheetRequest(
            mode: .pick,
            recipe: PlanRecipeChoice(source: .own, recipeID: a.recipeId, name: a.name, imageUrl: a.imageUrl, meta: ""),
            date: a.day.isEmpty ? (a.already ?? model.week) : a.day,
            start: model.week, persons: a.persons, cookDouble: a.cookDouble)
    }

    private func picked(_ result: PlanSheetResult) {
        guard case let .picked(date, persons, cookDouble) = result, let id = editingRecipeID,
              let i = assign.firstIndex(where: { $0.recipeId == id }) else { return }
        withAnimation {
            assign[i].day = dates.contains(date) ? date : assign[i].day
            assign[i].persons = persons
            assign[i].cookDouble = cookDouble
        }
        editingRecipeID = nil
    }

    private func dismissErrors() {
        withAnimation {
            saveError = nil
            loadError = nil
        }
    }

    private func previousWeek() {
        Task { await load(KiezenDates.add(model.week, -7)) }
    }

    private func nextWeek() {
        Task { await load(KiezenDates.add(model.week, 7)) }
    }

    private func startSave() {
        Task { await saveAndContinue() }
    }

    private func load(_ start: String?) async {
        guard let api = session.api else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.week(start)
            model.week = result.week
            dates = result.days.map(\.date)
            household = result.householdSize ?? 4
            weekPlan = Dictionary(uniqueKeysWithValues: result.days.map { ($0.date, $0.planItems(householdSize: household)) })
            savedIDs = []
            loadError = nil
            saveError = nil
            autoAssign()
            loaded = true
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            loadError = "Weekmenu ophalen mislukt. \(error.localizedDescription)"
        }
    }

    /// Eerste lege dag vanaf vandaag; zijn die op, dan de rustigste dag. Zelfde regels als de web-versie.
    private func autoAssign() {
        let start = dates.firstIndex(of: today) ?? 0
        let usable = Array(dates[start...])
        var load = Dictionary(uniqueKeysWithValues: dates.map { ($0, weekPlan[$0]?.count ?? 0) })
        assign = model.picked.filter { $0.kind == .own }.map { p in
            let isSame: (PlanItem) -> Bool = { $0.kind == .recipe && $0.recipeId == p.recipeID }
            if let already = dates.first(where: { d in (weekPlan[d] ?? []).contains(where: isSame) }) {
                let persons = weekPlan[already]?.first(where: isSame)?.persons ?? household
                return Assignment(recipeId: p.recipeID, name: p.name, imageUrl: p.imageUrl, day: "", already: already,
                                  persons: persons > 0 ? persons : household)
            }
            let day = usable.first { load[$0] == 0 }
                ?? usable.min { (load[$0] ?? 0) < (load[$1] ?? 0) } ?? ""
            if !day.isEmpty { load[day, default: 0] += 1 }
            return Assignment(recipeId: p.recipeID, name: p.name, imageUrl: p.imageUrl, day: day, persons: household)
        }
    }

    /// Elk ingepland recept als planregel opslaan (`POST /api/plan/entries`, met personen en kook dubbel).
    private func saveAndContinue() async {
        guard let api = session.api else { return }
        model.groceryPersons = Dictionary(assign.map { ($0.recipeId, $0.groceryPersons) }, uniquingKeysWith: { a, _ in a })
        // Niets op een dag gezet: het weekmenu blijft gelijk, dus opslaan is niet nodig.
        guard hasDays else { onNext(); return }
        saving = true
        saveError = nil
        defer { saving = false }
        for a in assign where !a.day.isEmpty && !savedIDs.contains(a.recipeId) {
            do {
                let body = PlanEntryCreateBody.recipe(a.recipeId, date: a.day,
                                                      persons: a.persons == household ? nil : a.persons,
                                                      cookDouble: a.cookDouble)
                _ = try await api.createPlanEntry(body)
                savedIDs.insert(a.recipeId)
            } catch {
                saveError = "\(a.name) opslaan mislukt: \(error.localizedDescription) Je keuzes staan er nog; probeer het opnieuw."
                return
            }
        }
        await OrderReminderScheduler.refresh(api: api)
        onNext()
    }
}
