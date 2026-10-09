import SwiftUI

/// Weekmenu plannen, vastzetten en controleren of alles op het AH-lijstje staat.
struct PlanView: View {
    @Environment(Session.self) private var session
    @State private var week: WeekResponse?
    @State private var allRecipes: [RecipeSummary] = []
    @State private var pickerDay: DayID?
    @State private var busy = false
    @State private var message: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let week {
                    if let errorText {
                        ErrorBanner(message: errorText, onDismiss: dismissError)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }

                    Section {
                        HStack {
                            Button(action: previousWeek) {
                                Label("Vorige week", systemImage: "chevron.left")
                                    .labelStyle(.iconOnly)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                            Spacer()
                            Text("Week van \(week.week)").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                            Spacer()
                            Button(action: nextWeek) {
                                Label("Volgende week", systemImage: "chevron.right")
                                    .labelStyle(.iconOnly)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                        }
                        .buttonStyle(.borderless)
                        .misoRow()
                    }

                    ForEach(week.days) { day in
                        Section {
                            ForEach(day.entries) { entry in
                                RecipeRow(recipe: entry.recipe)
                            }
                            .onDelete { offsets in
                                Task { await remove(from: day, at: offsets) }
                            }
                            Button {
                                pickerDay = DayID(date: day.date)
                            } label: {
                                Label("Recept toevoegen", systemImage: "plus")
                            }
                            .font(.misoButton).foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                        } header: {
                            HStack {
                                Text(day.label).misoSectionHeader()
                                if day.today { Text("vandaag").misoChip(.misoOrange) }
                            }
                        }
                        .misoRow()
                    }

                    statusSection(week.status)
                } else if let errorText {
                    ErrorStateView(message: errorText).listRowBackground(Color.clear)
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .misoScreen()
            .navigationTitle("Weekmenu")
            .refreshable { await load(week: week?.week) }
            .task { await load(week: nil) }
            .sheet(item: $pickerDay) { day in
                RecipePicker(recipes: allRecipes) { recipe in
                    Task { await add(recipe, on: day.date) }
                }
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ status: WeekStatus) -> some View {
        Section {
            if status.needed == 0 && status.unmatched.isEmpty {
                EmptyStateView(pose: "idea", title: "Nog niets gepland", message: "Voeg hierboven recepten toe, dan maakt Miso je boodschappenlijst.", size: 100)
            } else if status.complete {
                HStack(spacing: 12) {
                    MascotView(pose: "delighted", size: 64)
                    Label(status.needed == 1 ? "Het product staat op je AH-lijstje" : "Alle \(status.needed) producten staan op je AH-lijstje",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.misoBlue)
                }
                .padding(8).background(Color.misoMint, in: .rect(cornerRadius: 14))
            } else {
                if !status.missing.isEmpty {
                    Label("Nog \(plural(status.missing.count, "product", "producten")) niet op je lijstje", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.misoBlue)
                    ForEach(status.missing) { item in Text("\(item.quantity)× \(item.name)").font(.callout) }
                }
                if !status.unmatched.isEmpty {
                    Label("Geen AH-product gekoppeld", systemImage: "questionmark.circle").foregroundStyle(Color.misoBlue)
                    ForEach(status.unmatched, id: \.self) { Text($0).font(.callout) }
                }
            }
            if status.locked { Label("Weekmenu is vastgezet", systemImage: "lock.fill") }
            Button(status.locked ? "Weekmenu ontgrendelen" : "Weekmenu vastzetten", action: toggleLock)
                .buttonStyle(.misoPrimary)
                .disabled(busy)
            Button("Controleer en vul aan", action: checkList)
                .buttonStyle(.misoSecondary)
                .disabled(busy)
            if busy { ProgressView() }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Boodschappen").misoSectionHeader() }
        .misoRow()
    }

    private struct DayID: Identifiable { let date: String; var id: String { date } }

    // MARK: Acties

    private func dismissError() {
        withAnimation { errorText = nil }
    }

    private func previousWeek() {
        guard let week else { return }
        Task { await load(week: week.prevWeek) }
    }

    private func nextWeek() {
        guard let week else { return }
        Task { await load(week: week.nextWeek) }
    }

    private func toggleLock() {
        guard let week else { return }
        Task { await sync(locked: !week.status.locked) }
    }

    private func checkList() {
        Task { await sync(locked: nil) }
    }

    private func load(week weekStart: String?) async {
        guard let api = session.api else { return }
        do {
            let query = weekStart.map { [URLQueryItem(name: "week", value: $0)] } ?? []
            let result: WeekResponse = try await api.get("api/week", query: query)
            week = result
            let list: RecipesResponse = try await api.get("api/recipes")
            allRecipes = list.recipes
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            // Staat er al een weekmenu, dan blijft dat staan en komt de fout in een melding erboven.
            errorText = error.localizedDescription
        }
    }

    private func planDict(_ week: WeekResponse) -> [String: [Int]] {
        Dictionary(uniqueKeysWithValues: week.days.map { ($0.date, $0.recipes.map(\.id)) })
    }

    private func save(_ days: [String: [Int]], week current: WeekResponse) async {
        guard let api = session.api else { return }
        do {
            let result: SavePlanResult = try await api.post("api/plan", json: SavePlanBody(week: current.week, days: days))
            if !result.ok { errorText = "Opslaan van het weekmenu is mislukt." }
            await load(week: current.week)
        } catch {
            errorText = "Opslaan mislukt. \(error.localizedDescription)"
        }
    }

    private func add(_ recipe: RecipeSummary, on date: String) async {
        guard let week else { return }
        var days = planDict(week)
        days[date, default: []].append(recipe.id)
        await save(days, week: week)
    }

    private func remove(from day: PlanDay, at offsets: IndexSet) async {
        guard let week else { return }
        var days = planDict(week)
        days[day.date]?.remove(atOffsets: offsets)
        await save(days, week: week)
    }

    private func sync(locked: Bool?) async {
        guard let api = session.api, let current = week else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let result: SyncResult = try await api.post("api/plan/sync", json: SyncBody(week: current.week, locked: locked))
            if result.ok {
                let added = result.added ?? 0
                message = added > 0 ? "\(plural(added, "product", "producten")) toegevoegd aan je AH-lijstje." : nil
                await load(week: current.week)
            } else {
                message = result.error ?? "Mislukt"
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
