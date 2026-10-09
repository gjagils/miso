import SwiftUI

/// Weekmenu: per dag wat er gepland is (recept, restje, "hebben we al"), plannen via "+", verplaatsen,
/// personen aanpassen, en één knop om de nieuwe producten op het AH-lijstje te zetten.
struct PlanView: View {
    @Environment(Session.self) private var session
    @State private var model = WeekPlanModel()
    @State private var path: [PlanRoute] = []
    @State private var planRequest: PlanSheetRequest?
    @State private var pendingDelete: PlanItem?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let week = model.week {
                    if let errorText = model.errorText {
                        ErrorBanner(message: errorText, onDismiss: dismissError)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }

                    Section {
                        WeekNavigator(title: "Week van \(KiezenDates.short(week.week))",
                                      onPrevious: previousWeek, onNext: nextWeek)
                    }
                    .misoRow()

                    ForEach(week.days) { day in
                        Section {
                            let items = model.items(for: day)
                            ForEach(items) { item in
                                PlanItemRow(item: item,
                                            persons: model.persons(for: item),
                                            profile: model.profile(for: item),
                                            onOpenRecipe: item.recipeId.map { id in { openRecipe(id) } },
                                            onPersons: item.isEditable ? { setPersons($0, for: item) } : nil)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if item.isEditable {
                                            Button("Verwijder", systemImage: "trash") { askDelete(item) }
                                                .tint(.red)
                                            Button("Verplaats naar…", systemImage: "calendar") { move(item) }
                                                .tint(Color.misoBlue)
                                        }
                                    }
                            }
                            if items.isEmpty {
                                Text("Nog niets gepland").font(.misoBody).foregroundStyle(.secondary)
                            }
                        } header: {
                            PlanDayHeader(day: day) { add(on: day) }
                        }
                        .misoRow()
                    }

                    GroceriesSection(status: week.status, pushing: model.pushing, result: model.pushResult,
                                     onPush: pushToList)

                    if let health = model.health, health.dagen > 0 {
                        HealthSection(health: health)
                    }

                    Section {
                        NavigationLink(value: PlanRoute.freezer) {
                            Label("Vriezer", systemImage: "snowflake")
                                .font(.misoButton)
                                .foregroundStyle(Color.misoBlue)
                                .frame(minHeight: 44)
                        }
                    }
                    .misoRow()
                } else if let errorText = model.errorText {
                    ErrorStateView(message: errorText).listRowBackground(Color.clear)
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .misoScreen()
            .navigationTitle("Weekmenu")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: PlanRoute.freezer) {
                        Label("Vriezer", systemImage: "snowflake")
                    }
                }
            }
            .navigationDestination(for: PlanRoute.self) { route in
                switch route {
                case .recipe(let id): RecipeDetailView(recipeID: id)
                case .freezer: FreezerView(week: model.week?.week, firstFreeDay: model.firstFreeDay)
                }
            }
            .refreshable { await reload() }
            .task { await load() }
            .sheet(item: $planRequest) { request in
                PlanSheet(request: request, onDone: planned)
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible,
                                presenting: pendingDelete) { item in
                Button("Verwijder", role: .destructive) { delete(item) }
                Button("Annuleer", role: .cancel) {}
            } message: { _ in
                Text("De rest-dag gaat ook weg.")
            }
        }
    }

    private var deleteTitle: String {
        pendingDelete.map { "\($0.title) van het weekmenu halen?" } ?? ""
    }

    // MARK: Acties

    private func dismissError() {
        withAnimation { model.errorText = nil }
    }

    private func load() async {
        guard let api = session.api else { return }
        await model.load(api: api, week: model.week?.week)
    }

    private func reload() async {
        guard let api = session.api else { return }
        await model.afterChange(api: api)
    }

    private func previousWeek() {
        guard let api = session.api, let week = model.week else { return }
        Task { await model.showWeek(week.prevWeek, api: api) }
    }

    private func nextWeek() {
        guard let api = session.api, let week = model.week else { return }
        Task { await model.showWeek(week.nextWeek, api: api) }
    }

    private func openRecipe(_ id: Int) {
        path.append(.recipe(id))
    }

    private func add(on day: PlanDay) {
        planRequest = PlanSheetRequest(showTabs: true, date: day.date, start: model.week?.week)
    }

    private func move(_ item: PlanItem) {
        planRequest = PlanSheetRequest(mode: .move(item), date: item.date, start: model.week?.week)
    }

    private func planned(_ result: PlanSheetResult) {
        Task { await reload() }
    }

    /// Een kookdag met rest-dag eerst bevestigen (de rest gaat mee); anders direct weghalen.
    private func askDelete(_ item: PlanItem) {
        if item.leftoverEntryIds.isEmpty {
            delete(item)
        } else {
            pendingDelete = item
            confirmingDelete = true
        }
    }

    private func delete(_ item: PlanItem) {
        guard let api = session.api else { return }
        Task { await model.delete(item, api: api) }
    }

    private func setPersons(_ value: Int, for item: PlanItem) {
        guard let api = session.api else { return }
        model.setPersons(value, for: item, api: api)
    }

    private func pushToList() {
        guard let api = session.api else { return }
        Task { await model.pushToList(api: api) }
    }
}
