import SwiftUI

/// Recept bewerken: naam, porties, tijd, beschrijving, ingrediëntregels en bereiding.
/// Ongewijzigde ingrediëntregels houden hun AH-koppeling; nieuwe regels koppelt de server meteen.
struct RecipeEditView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let recipe: RecipeDetail
    let onSaved: (RecipeDetail) -> Void

    @State private var draft: RecipeDraft
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDiscard = false

    init(recipe: RecipeDetail, onSaved: @escaping (RecipeDetail) -> Void) {
        self.recipe = recipe
        self.onSaved = onSaved
        _draft = State(initialValue: RecipeDraft(recipe: recipe))
    }

    private var hasChanges: Bool { !draft.patch(against: recipe).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if let errorText {
                    ErrorBanner(message: errorText, onDismiss: dismissError)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                Section {
                    TextField("Naam", text: $draft.name, prompt: Text("Naam van het recept"))
                        .font(.misoHeadline)
                        .frame(minHeight: 44)
                    LabeledContent("Porties") {
                        TextField("Porties", text: $draft.servings, prompt: Text("Bijv. 4 personen"))
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: 44)
                    LabeledContent("Tijd") {
                        TextField("Tijd", text: $draft.totalTime, prompt: Text("Bijv. 30 min"))
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: 44)
                    TextField("Beschrijving", text: $draft.description, prompt: Text("Korte beschrijving"),
                              axis: .vertical)
                        .lineLimit(2...8)
                        .frame(minHeight: 44)
                } header: {
                    Text("Recept").misoSectionHeader()
                }
                .misoRow()

                EditableLinesSection(title: "Ingrediënten", placeholder: "Bijv. 2 gele paprika's",
                                     addTitle: "Ingrediënt toevoegen", lineLabel: { "Ingrediënt \($0)" },
                                     lines: $draft.ingredients)

                EditableLinesSection(title: "Bereiding", placeholder: "Wat doe je in deze stap?",
                                     addTitle: "Stap toevoegen", lineLabel: { "Stap \($0)" },
                                     lines: $draft.steps, multiline: true)
            }
            .misoScreen()
            // Altijd in bewerkmodus: regels zijn direct te verwijderen en te verslepen.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Recept bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", action: cancel)
                        .confirmationDialog("Wijzigingen weggooien?", isPresented: $confirmDiscard,
                                            titleVisibility: .visible) {
                            Button("Weggooien", role: .destructive, action: close)
                            Button("Verder bewerken", role: .cancel) {}
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Bewaar", action: startSave)
                            .disabled(!draft.canSave || !hasChanges)
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges)
        }
    }

    // MARK: Acties

    private func dismissError() {
        withAnimation { errorText = nil }
    }

    private func cancel() {
        if hasChanges { confirmDiscard = true } else { close() }
    }

    private func close() {
        dismiss()
    }

    private func startSave() {
        Task { await save() }
    }

    private func save() async {
        guard let api = session.api, draft.canSave else { return }
        let body = draft.patch(against: recipe)
        guard !body.isEmpty else { close(); return }
        saving = true
        defer { saving = false }
        do {
            let updated = try await api.updateRecipe(recipe.id, body)
            onSaved(updated)
            close()
        } catch {
            errorText = "Opslaan is niet gelukt. \(error.localizedDescription)"
        }
    }
}
