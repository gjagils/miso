import SwiftUI

struct RecipesView: View {
    @Environment(Session.self) private var session
    @State private var recipes: [RecipeSummary] = []
    @State private var search = ""
    @State private var showImport = false
    @State private var errorText: String?
    @State private var loaded = false

    private var filtered: [RecipeSummary] {
        search.isEmpty ? recipes : recipes.filter { $0.name.localizedCaseInsensitiveContains(search) }
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
                    EmptyStateView(pose: "confused", title: "Niets gevonden",
                                   message: "Probeer een andere zoekterm.")
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
                    Button { showImport = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Recept toevoegen")
                }
            }
            .sheet(isPresented: $showImport, onDismiss: { Task { await load() } }) { ImportView() }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @MainActor
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
