import SwiftUI

struct RecipesView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(FamilyModel.self) private var family
    @State private var recipes: [RecipeSummary] = []
    @State private var search = ""
    @State private var filter: RecipeFilter = .all
    @State private var showImport = false
    @State private var errorText: String?
    @State private var loaded = false

    private var filtered: [RecipeSummary] {
        search.isEmpty ? recipes : recipes.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecipeFilterBar(selection: $filter)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if let errorText {
                    ErrorStateView(message: errorText).listRowBackground(Color.clear)
                } else if loaded && recipes.isEmpty {
                    EmptyStateView(pose: "hungry", title: filter.emptyTitle, message: filter.emptyMessage)
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
            .navigationDestination(for: ReviewRoute.self) { _ in ReviewView() }
            .toolbar {
                if family.isParent {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: ReviewRoute()) {
                            Label("Opruimen", systemImage: "archivebox")
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityHint("Recepten die jullie nooit of al lang niet kiezen")
                    }
                }
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
            .task(id: filter) { await load() }
            // Recept bewerkt, verwijderd, favoriet of opgeruimd: lijst verversen.
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
        let current = filter
        do {
            let result = try await api.recipes(filter: current)
            guard current == filter else { return }
            recipes = result
            loaded = true
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            errorText = error.localizedDescription
        }
    }
}

/// Route naar het Opruimen-scherm.
struct ReviewRoute: Hashable {}
