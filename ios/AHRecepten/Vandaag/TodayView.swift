import SwiftUI

/// Vandaag: "Ik ga koken. Wat moet ik doen?" Het gerecht van vandaag groot met "Start met koken",
/// morgen en overmorgen klein eronder, en de banner voor volgende week.
struct TodayView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = TodayModel()
    @State private var nextWeek = NextWeekModel()
    @State private var cookRecipe: RecipeDetail?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let errorText = model.errorText {
                        ErrorBanner(message: errorText, onDismiss: dismissError)
                    }
                    if let main = model.mainItem {
                        TodayHeroCard(item: main, recipe: model.todayRecipe, onCook: startCooking)
                        ForEach(model.otherTodayItems) { item in
                            UpcomingDayRow(title: "Ook vandaag", items: [item])
                        }
                    } else if model.loaded && model.errorText == nil {
                        TodaySuggestionsCard(suggestions: model.suggestions, planningID: model.planningSuggestion,
                                             onPick: pick, onPlan: planToday)
                    } else if !model.loaded {
                        ProgressView().padding(.top, 40)
                    }
                    if model.loaded {
                        ForEach(Array(model.upcoming.enumerated()), id: \.element.date) { offset, day in
                            UpcomingDayRow(title: offset == 0 ? "Morgen" : KiezenDates.label(day.date),
                                           items: day.items)
                        }
                    }
                    NextWeekBanner(model: nextWeek, onPlan: planNextWeek, onSuggest: suggest,
                                   onApply: applySuggestions, onDismissSuggestions: dismissSuggestions)
                    if model.loaded {
                        Button("Hele week bekijken", systemImage: "list.bullet.rectangle", action: showWeek)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                }
                .padding(16)
            }
            .background(Color.misoCream)
            .navigationTitle("Vandaag")
            .navigationDestination(for: RecipeSummary.self) { RecipeDetailView(recipeID: $0.id) }
            .refreshable { await load() }
            .task { await load() }
            // Elders ingepland, of een recept bewerkt/verwijderd: opnieuw ophalen.
            .onChange(of: router.planVersion) { reload() }
            .onChange(of: router.recipesVersion) { reload() }
            .fullScreenCover(item: $cookRecipe) { recipe in
                CookView(recipe: recipe)
            }
        }
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

    private func pick(_ suggestion: TodaySuggestion) {
        guard let api = session.api else { return }
        Task {
            if await model.plan(suggestion, api: api) {
                router.planChanged()
                AccessibilityNotification.Announcement("\(suggestion.title) staat vandaag op het menu").post()
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

    private func showWeek() {
        router.tab = .plan
    }

    private func suggest() {
        guard let api = session.api else { return }
        Task { await nextWeek.suggest(api: api) }
    }

    private func applySuggestions() {
        guard let api = session.api else { return }
        Task {
            if await nextWeek.apply(api: api) { router.planChanged() }
        }
    }

    private func dismissSuggestions() {
        nextWeek.dismissSuggestions()
    }
}
