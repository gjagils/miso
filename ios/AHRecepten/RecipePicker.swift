import SwiftUI

/// Recept kiezen om aan een dag toe te voegen.
struct RecipePicker: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [RecipeSummary]
    let onPick: (RecipeSummary) -> Void
    @State private var search = ""

    private var filtered: [RecipeSummary] {
        search.isEmpty ? recipes : recipes.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { recipe in
                Button {
                    pick(recipe)
                } label: { RecipeRow(recipe: recipe) }
                .buttonStyle(.plain)
                .misoRow()
            }
            .misoScreen()
            .overlay {
                if !search.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Zoek recept")
            .navigationTitle("Kies een recept")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", action: cancel) }
            }
        }
    }

    private func pick(_ recipe: RecipeSummary) {
        onPick(recipe)
        dismiss()
    }

    private func cancel() {
        dismiss()
    }
}
