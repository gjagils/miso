import SwiftUI

/// Recepten → Opruimen (zoals /recepten/opruimen): recepten die jullie nooit of al lang niet kiezen.
/// Per recept Bewaren, Uit mijn hoofd of Opruimen; de rij verdwijnt als het gelukt is.
struct ReviewView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var recipes: [ReviewRecipe] = []
    @State private var totalPlans = 0
    @State private var loaded = false
    @State private var errorText: String?
    @State private var busyID: Int?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(intro)
                    .font(.callout)
                    .foregroundStyle(Color.misoBlue)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorText {
                    ErrorBanner(message: errorText, onDismiss: dismissError)
                }
                if loaded && recipes.isEmpty && errorText == nil {
                    EmptyStateView(pose: "celebrate", title: "Alles netjes",
                                   message: "Er zijn geen recepten om op te ruimen.")
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                }
                ForEach(recipes) { recipe in
                    ReviewRow(recipe: recipe, busy: busyID == recipe.id,
                              onKeep: { act(.keep, on: recipe) },
                              onByHeart: { act(.byHeartKeep, on: recipe) },
                              onArchive: { act(.archive, on: recipe) })
                        .misoCard()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(16)
        }
        .background(Color.misoCream)
        .navigationTitle("Opruimen")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: RecipeSummaryLink.self) { RecipeDetailView(recipeID: $0.id) }
        .refreshable { await load() }
        .task { await load() }
    }

    private var intro: String {
        "Jullie hebben \(totalPlans) keer een recept gepland. Deze recepten kiezen jullie nooit of al lang niet. "
            + "Bewaar ze, zet ze op “uit mijn hoofd” (alleen voor de boodschappen), of ruim ze op. "
            + "Opgeruimde recepten haal je terug bij Recepten → Opgeruimd."
    }

    private func dismissError() {
        withAnimation { errorText = nil }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            let result = try await api.recipesReview()
            recipes = result.recipes
            totalPlans = result.totalPlans
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
        loaded = true
    }

    private func act(_ body: RecipeFlagsBody, on recipe: ReviewRecipe) {
        guard let api = session.api, busyID == nil else { return }
        busyID = recipe.id
        Task {
            defer { busyID = nil }
            do {
                let result = try await api.setRecipeFlags(recipe.id, body)
                guard result.ok else { throw APIError(message: "Opslaan lukte niet.") }
                withAnimation { recipes.removeAll { $0.id == recipe.id } }
                router.recipesChanged()
                let done = body.archived == true ? "opgeruimd" : body.byHeart == true ? "op uit mijn hoofd gezet" : "bewaard"
                AccessibilityNotification.Announcement("\(recipe.name) \(done)").post()
            } catch {
                withAnimation { errorText = "\(recipe.name): \(error.localizedDescription)" }
            }
        }
    }
}
