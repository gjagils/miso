import SwiftUI

/// Vandaag: "Ik ga koken. Wat moet ik doen?" Het gerecht van vandaag groot met "Start met koken",
/// morgen en overmorgen klein eronder (ook over de weekgrens), en de banner voor volgende week.
struct TodayView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = TodayModel()
    @State private var nextWeek = NextWeekModel()
    @State private var cookRecipe: RecipeDetail?
    /// Idee waar je op tikte; eerst bevestigen ("Dit koken we" / "Terug").
    @State private var pendingIdea: TodaySuggestion?
    @State private var confirmingIdea = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let errorText = model.errorText {
                        ErrorBanner(message: errorText, onDismiss: dismissError)
                    }
                    tonight
                    if model.loaded {
                        upcoming
                    }
                    NextWeekBanner(model: nextWeek, onPlan: planNextWeek)
                    if model.loaded {
                        NavigationLink(value: WeekmenuRoute()) {
                            Label("Hele week bekijken", systemImage: "list.bullet.rectangle")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.misoBlue)
                                .frame(minHeight: 44)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.misoCream)
            .navigationTitle("Vandaag")
            .navigationDestination(for: RecipeSummary.self) { RecipeDetailView(recipeID: $0.id) }
            .navigationDestination(for: WeekmenuRoute.self) { PlanView(initialWeek: $0.week) }
            .refreshable { await load() }
            .task { await load() }
            // Elders ingepland, of een recept bewerkt/verwijderd: opnieuw ophalen.
            .onChange(of: router.planVersion) { reload() }
            .onChange(of: router.recipesVersion) { reload() }
            .fullScreenCover(item: $cookRecipe) { recipe in
                CookView(recipe: recipe)
            }
            .confirmationDialog(ideaTitle, isPresented: $confirmingIdea, titleVisibility: .visible,
                                presenting: pendingIdea) { idea in
                Button("Dit koken we") { plan(idea) }
                Button("Terug", role: .cancel) {}
            } message: { idea in
                switch idea.kind {
                case .recipe: Text("Miso zet het op het menu van vandaag en opent de kookmodus.")
                case .freezer: Text("Miso zet “Iets uit de vriezer” op het menu van vandaag.")
                }
            }
        }
    }

    @ViewBuilder private var tonight: some View {
        if let main = model.mainItem {
            TodayHeroCard(item: main, recipe: model.todayRecipe, onCook: startCooking, onSomethingElse: planToday)
            ForEach(model.otherTodayItems) { item in
                UpcomingDayRow(title: "Ook vandaag", items: [item])
            }
        } else if model.loaded && model.errorText == nil {
            TodaySuggestionsCard(suggestions: model.suggestions, planningID: model.planningSuggestion,
                                 onPick: ask, onPlan: planToday)
        } else if !model.loaded {
            ProgressView().padding(.top, 40)
        }
    }

    @ViewBuilder private var upcoming: some View {
        ForEach(Array(model.upcoming.enumerated()), id: \.element.date) { offset, day in
            UpcomingDayRow(title: offset == 0 ? "Morgen" : "Overmorgen · \(KiezenDates.label(day.date))",
                           items: day.items)
        }
    }

    private var ideaTitle: String {
        pendingIdea.map { "Vanavond: \($0.title)?" } ?? ""
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        guard let api = session.api else { return }
        async let status: Void = nextWeek.load(api: api)
        await model.load(api: api)
        await status
    }

    // MARK: Acties

    private func startCooking() {
        cookRecipe = model.todayRecipe
    }

    private func ask(_ idea: TodaySuggestion) {
        pendingIdea = idea
        confirmingIdea = true
    }

    /// Bevestigd: inplannen voor vandaag en (bij een recept) meteen de kookmodus openen.
    private func plan(_ idea: TodaySuggestion) {
        guard let api = session.api else { return }
        Task {
            guard await model.plan(idea, api: api) else { return }
            router.planChanged()
            AccessibilityNotification.Announcement("\(idea.title) staat vandaag op het menu").post()
            if case .recipe = idea.kind, let recipe = model.todayRecipe, !recipe.isByHeart {
                cookRecipe = recipe
            }
        }
    }

    private func dismissError() {
        withAnimation { model.dismissError() }
    }

    private func planToday() {
        router.planWeek(KiezenDates.today)
    }

    private func planNextWeek() {
        router.planWeek(nextWeek.status?.week ?? KiezenDates.add(PlannenLogic.monday(of: KiezenDates.today), 7))
    }
}
