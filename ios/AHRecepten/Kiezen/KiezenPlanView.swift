import SwiftUI

// MARK: - Stap 2: inplannen

struct KiezenPlanView: View {
    @Environment(Session.self) private var session
    @Environment(KiezenModel.self) private var model
    let onNext: () -> Void

    @State private var dates: [String] = []
    @State private var weekPlan: [String: [RecipeSummary]] = [:]
    @State private var assign: [Assignment] = []
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
                    let existing = PlanEntry.entries(date: day, recipes: weekPlan[day] ?? [])
                    let mine = assign.filter { $0.day == day }
                    if !(day < today && existing.isEmpty && mine.isEmpty) {
                        Section {
                            ForEach(existing) { entry in
                                HStack {
                                    Text(entry.recipe.name).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("al gepland").misoChip(.misoLilac)
                                }
                                .frame(minHeight: 32)
                                .accessibilityElement(children: .combine)
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
    }

    private func assignRow(_ a: Assignment) -> some View {
        HStack(spacing: 12) {
            RecipeImage(path: a.imageUrl, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                    .lineLimit(2)
                if let already = a.already, a.day.isEmpty {
                    Text("staat al op \(KiezenDates.label(already).lowercased())").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Dag voor \(a.name)", selection: dayBinding(a.recipeId)) {
                    ForEach(dates, id: \.self) { d in Text(KiezenDates.label(d)).tag(d) }
                    Text("Niet inplannen").tag("")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.misoOrange)
                .fixedSize()
                .accessibilityLabel("Dag voor \(a.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
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
            weekPlan = Dictionary(uniqueKeysWithValues: result.days.map { ($0.date, $0.recipes) })
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
            if let already = dates.first(where: { d in (weekPlan[d] ?? []).contains { $0.id == p.recipeID } }) {
                return Assignment(recipeId: p.recipeID, name: p.name, imageUrl: p.imageUrl, day: "", already: already)
            }
            let day = usable.first { load[$0] == 0 }
                ?? usable.min { (load[$0] ?? 0) < (load[$1] ?? 0) } ?? ""
            if !day.isEmpty { load[day, default: 0] += 1 }
            return Assignment(recipeId: p.recipeID, name: p.name, imageUrl: p.imageUrl, day: day)
        }
    }

    private func saveAndContinue() async {
        guard let api = session.api else { return }
        // Niets op een dag gezet: het weekmenu blijft gelijk, dus opslaan is niet nodig.
        guard hasDays else { onNext(); return }
        var days: [String: [Int]] = [:]
        for d in dates { days[d] = (weekPlan[d] ?? []).map(\.id) }
        for a in assign where !a.day.isEmpty { days[a.day, default: []].append(a.recipeId) }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            let result = try await api.savePlan(week: model.week, days: days)
            if result.ok { onNext() } else { saveError = "Opslaan mislukt. Je keuzes staan er nog; probeer het opnieuw." }
        } catch {
            saveError = "Opslaan mislukt: \(error.localizedDescription) Je keuzes staan er nog; probeer het opnieuw."
        }
    }
}
