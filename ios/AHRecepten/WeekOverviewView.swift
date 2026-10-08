import SwiftUI

/// Gezinsweergave: wat staat er vandaag en deze week op het menu.
struct WeekOverviewView: View {
    @Environment(Session.self) private var session
    @State private var week: WeekResponse?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let week {
                        if week.days.allSatisfy({ $0.recipes.isEmpty }) {
                            EmptyStateView(pose: "idea", title: "Nog niets op de planning",
                                           message: "Kies bij Weekmenu wat jullie deze week eten.")
                                .misoCard()
                        }
                        ForEach(week.days) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(day.label).font(.misoHeadline).foregroundStyle(Color.misoBlue)
                                    if day.today { Text("vandaag").misoChip(.misoOrange) }
                                    Spacer()
                                }
                                if day.recipes.isEmpty {
                                    Text("Niets gepland").font(.misoBody).foregroundStyle(.secondary)
                                }
                                ForEach(Array(day.recipes.enumerated()), id: \.offset) { _, recipe in
                                    NavigationLink(value: recipe) {
                                        HStack {
                                            RecipeRow(recipe: recipe)
                                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                                .foregroundStyle(.secondary).accessibilityHidden(true)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .misoCard()
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.misoOrange, lineWidth: day.today ? 2 : 0)
                            )
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

    @MainActor
    private func load() async {
        guard let api = session.api else { return }
        do {
            let result: WeekResponse = try await api.get("api/week")
            week = result
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
