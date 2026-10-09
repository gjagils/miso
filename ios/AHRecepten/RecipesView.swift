import SwiftUI

struct RecipesView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var recipes: [RecipeSummary] = []
    @State private var search = ""
    @State private var showImport = false
    @State private var errorText: String?
    @State private var loaded = false

    private var filtered: [RecipeSummary] {
        search.isEmpty ? recipes : recipes.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    ErrorStateView(message: errorText).listRowBackground(Color.clear)
                } else if loaded && recipes.isEmpty {
                    EmptyStateView(pose: "hungry", title: "Nog geen recepten",
                                   message: "Tik op + om je eerste recept toe te voegen.")
                        .listRowBackground(Color.clear)
                } else if loaded && filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { recipe in
                    NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                        .misoRow()
                }
            }
            .misoScreen()
            .searchable(text: $search, prompt: "Zoek recept")
            .navigationTitle("Recepten")
            .navigationDestination(for: RecipeSummary.self) { RecipeDetailView(recipeID: $0.id) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: showImporter) {
                        Label("Recept toevoegen", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                }
            }
            .sheet(isPresented: $showImport, onDismiss: reload) { ImportView() }
            .refreshable { await load() }
            .task { await load() }
            // Recept bewerkt of verwijderd: lijst verversen.
            .onChange(of: router.recipesVersion) { reload() }
        }
    }

    private func showImporter() {
        showImport = true
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            let result: RecipesResponse = try await api.get("api/recipes")
            recipes = result.recipes
            loaded = true
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
