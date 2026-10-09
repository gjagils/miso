import SwiftUI

/// Gezinsweergave: wat staat er vandaag en deze week op het menu, plus de banner voor volgende week.
struct WeekOverviewView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var week: WeekResponse?
    @State private var errorText: String?
    @State private var nextWeek = NextWeekModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    NextWeekBanner(model: nextWeek, onPlan: planNextWeek, onSuggest: suggest,
                                   onApply: applySuggestions, onDismissSuggestions: dismissSuggestions)
                    if let week {
                        if let errorText {
                            ErrorBanner(message: errorText, onDismiss: dismissError)
                        }
                        let household = week.householdSize ?? 4
                        if week.days.allSatisfy({ $0.planItems(householdSize: household).isEmpty }) {
                            EmptyStateView(pose: "idea", title: "Nog niets op de planning",
                                           message: "Kies bij Weekmenu wat jullie deze week eten.")
                                .misoCard()
                        }
                        ForEach(week.days) { day in
                            OverviewDayCard(day: day, items: day.planItems(householdSize: household))
                        }
                    } else if let errorText {
                        ErrorStateView(message: errorText)
                    } else {
                        ProgressView().padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .background(Color.misoCream)
            .navigationTitle("Deze week")
            .navigationDestination(for: RecipeSummary.self) { RecipeDetailView(recipeID: $0.id) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    // MARK: Acties

    private func dismissError() {
        withAnimation { errorText = nil }
    }

    private func planNextWeek() {
        router.planWeek(nextWeek.status?.week ?? KiezenDates.add(week?.week ?? KiezenDates.today, 7))
    }

    private func suggest() {
        guard let api = session.api else { return }
        Task { await nextWeek.suggest(api: api) }
    }

    private func applySuggestions() {
        guard let api = session.api else { return }
        Task { _ = await nextWeek.apply(api: api) }
    }

    private func dismissSuggestions() {
        nextWeek.dismissSuggestions()
    }

    private func load() async {
        guard let api = session.api else { return }
        async let status: Void = nextWeek.load(api: api)
        do {
            let result: WeekResponse = try await api.week(nil)
            week = result
            errorText = nil
        } catch {
            if (error as? URLError)?.code != .cancelled { errorText = error.localizedDescription }
        }
        await status
    }
}
