import SwiftUI

/// Tabblad "Recept": gekozen recept, of zoeken in eigen recepten en Allerhande (zoals Wat eten we? stap 1).
struct PlanRecipePanel: View {
    @Bindable var model: PlanSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let chosen = model.chosen {
                if model.canChangeRecipe {
                    PlanChosenRecipeRow(choice: chosen, onChange: clearChoice)
                } else {
                    PlanChosenRecipeRow(choice: chosen)
                }
            } else {
                TextField("Zoek in je recepten en Allerhande", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .misoField()
                    .accessibilityLabel("Zoek een recept")
                VStack(alignment: .leading, spacing: 4) {
                    if model.ownHits.isEmpty && !model.trimmedQuery.isEmpty {
                        Text("Geen eigen recept met \"\(model.trimmedQuery)\".")
                            .font(.misoCaption).foregroundStyle(.secondary)
                    }
                    ForEach(model.ownHits) { recipe in
                        let choice = PlanRecipeChoice.own(recipe)
                        PlanRecipeResultRow(choice: choice) { model.choose(choice) }
                    }
                    if model.ahSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Miso snuffelt in Allerhande...").font(.misoCaption).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    } else if let status = model.ahStatus {
                        Text(status).font(.misoCaption).foregroundStyle(.secondary)
                    }
                    ForEach(model.ahResults) { hit in
                        let choice = PlanRecipeChoice.allerhande(hit)
                        PlanRecipeResultRow(choice: choice) { model.choose(choice) }
                    }
                }
                .misoCard(padding: 12)
            }
        }
    }

    private func clearChoice() {
        model.clearChoice()
    }
}
