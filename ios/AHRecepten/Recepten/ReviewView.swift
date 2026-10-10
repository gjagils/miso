import SwiftUI

/// Recepten → Opruimen (zoals /recepten/opruimen): recepten die jullie nooit of al lang niet kiezen.
/// Per recept Bewaren, Uit mijn hoofd of Opruimen; de rij verdwijnt en je kunt het ongedaan maken.
/// Pas zinvol na een paar weken plannen (de server zegt dan `too_early`).
struct ReviewView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var recipes: [ReviewRecipe] = []
    @State private var totalPlans = 0
    @State private var minPlans = 30
    @State private var tooEarly = false
    @State private var loaded = false
    @State private var errorText: String?
    @State private var busyID: Int?
    /// Laatste keuze, om ongedaan te maken (recept, keuze, oude plek in de lijst).
    @State private var lastAction: (recipe: ReviewRecipe, action: ReviewAction, index: Int)?
    @State private var undoing = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if tooEarly {
                    EmptyStateView(pose: "sleepy", title: "Nog te vroeg",
                                   message: "Plan eerst een paar weken, dan ziet Miso welke recepten jullie nooit kiezen "
                                       + "(\(totalPlans) van \(minPlans)).")
                } else if loaded {
                    Text(intro)
                        .font(.callout)
                        .foregroundStyle(Color.misoBlue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorText {
                    ErrorBanner(message: errorText, onDismiss: dismissError)
                }
                if let lastAction {
                    undoRow(lastAction.action.done(lastAction.recipe.name))
                }
                if loaded && !tooEarly && recipes.isEmpty && errorText == nil {
                    EmptyStateView(pose: "celebrate", title: "Alles netjes",
                                   message: "Er zijn geen recepten om op te ruimen.")
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                }
                ForEach(recipes) { recipe in
                    ReviewRow(recipe: recipe, busy: busyID == recipe.id,
                              onKeep: { act(.keep, on: recipe) },
                              onByHeart: { act(.byHeart, on: recipe) },
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

    private func undoRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.misoInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: undo) {
                if undoing { ProgressView() } else { Text("Ongedaan maken").underline() }
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(Color.misoInk)
            .frame(minHeight: 44)
            .buttonStyle(.plain)
            .disabled(undoing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.misoMint, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
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
            minPlans = result.minPlans
            tooEarly = result.tooEarly
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
        loaded = true
    }

    private func act(_ action: ReviewAction, on recipe: ReviewRecipe) {
        guard let api = session.api, busyID == nil else { return }
        busyID = recipe.id
        Task {
            defer { busyID = nil }
            do {
                let result = try await api.setRecipeFlags(recipe.id, action.body)
                guard result.ok else { throw APIError(message: "Opslaan lukte niet.") }
                let index = recipes.firstIndex { $0.id == recipe.id } ?? 0
                withAnimation {
                    recipes.removeAll { $0.id == recipe.id }
                    lastAction = (recipe, action, index)
                }
                router.recipesChanged()
                AccessibilityNotification.Announcement(action.done(recipe.name)).post()
            } catch {
                withAnimation { errorText = "\(recipe.name): \(error.localizedDescription)" }
            }
        }
    }

    private func undo() {
        guard let api = session.api, let last = lastAction else { return }
        undoing = true
        Task {
            defer { undoing = false }
            do {
                let result = try await api.setRecipeFlags(last.recipe.id, last.action.undoBody)
                guard result.ok else { throw APIError(message: "Ongedaan maken lukte niet.") }
                withAnimation {
                    recipes.insert(last.recipe, at: min(last.index, recipes.count))
                    lastAction = nil
                }
                router.recipesChanged()
                AccessibilityNotification.Announcement("Ongedaan gemaakt").post()
            } catch {
                withAnimation { errorText = error.localizedDescription }
            }
        }
    }
}
