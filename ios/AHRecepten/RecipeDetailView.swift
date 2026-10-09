import SwiftUI

struct RecipeDetailView: View {
    @Environment(Session.self) private var session
    let recipeID: Int
    @State private var recipe: RecipeDetail?
    @State private var cookRecipe: RecipeDetail?
    @State private var busy = false
    @State private var message: String?
    @State private var errorText: String?
    @State private var planRequest: PlanSheetRequest?
    @State private var plannedMessage: String?

    var body: some View {
        List {
            if let recipe {
                Section {
                    VStack(spacing: 12) {
                        RecipeImage(path: recipe.imageUrl, size: 200)
                        let meta = [recipe.servings, recipe.totalTime].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty { Text(meta).font(.misoCaption).foregroundStyle(.secondary) }
                        if !recipe.description.isEmpty { Text(recipe.description).font(.misoBody) }
                        Button("Inplannen", systemImage: "calendar.badge.plus", action: startPlanning)
                            .buttonStyle(.misoPrimary)
                        Button("Kookmodus", systemImage: "flame", action: startCooking)
                            .buttonStyle(.misoSecondary)
                        if let plannedMessage {
                            HStack(spacing: 10) {
                                MascotView(pose: "celebrate", size: 48)
                                Text(plannedMessage).font(.callout).foregroundStyle(Color.misoInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color.misoMint, in: .rect(cornerRadius: 14))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .misoRow()
                }

                Section {
                    switch recipe.gfMode {
                    case .extra: Text("Extra glutenvrij product erbij (voor 1 persoon)")
                    case .replace: Text("Ingrediënt voor iedereen vervangen")
                    case .none: Text("Nog niet ingesteld").foregroundStyle(.secondary)
                    }
                    if !recipe.gfNote.isEmpty { Text(recipe.gfNote).font(.callout) }
                    Button(action: startGlutenFreeSuggestion) {
                        if busy { ProgressView() } else { Label("Voorstel van Claude", systemImage: "wand.and.stars") }
                    }
                    .buttonStyle(.misoSecondary)
                    .disabled(busy)
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Glutenvrij voor minstens 1 persoon").misoSectionHeader() }
                .misoRow()

                Section {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ingredient in
                        IngredientRow(ingredient: ingredient)
                    }
                } header: { Text("Ingrediënten").misoSectionHeader() }
                .misoRow()

                Section {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                                .foregroundStyle(Color.misoInk)
                                .frame(width: 28, height: 28)
                                .background(Color.misoOrange, in: Circle())
                                .accessibilityHidden(true)
                            Text(step)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Stap \(index + 1): \(step)")
                    }
                } header: { Text("Bereiding").misoSectionHeader() }
                .misoRow()

                if let url = URL(string: recipe.sourceUrl), !recipe.sourceUrl.isEmpty {
                    Section {
                        Link("Bron openen", destination: url).foregroundStyle(Color.misoBlue).font(.misoButton)
                            .frame(minHeight: 44)
                    }
                    .misoRow()
                }
            } else if let errorText {
                ErrorStateView(message: errorText).listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .misoScreen()
        .navigationTitle(recipe?.name ?? "Recept")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $cookRecipe) { recipe in
            CookView(recipe: recipe)
        }
        .sheet(item: $planRequest) { request in
            PlanSheet(request: request, onDone: planned)
        }
        .task { await load() }
    }

    private func startCooking() {
        cookRecipe = recipe
    }

    private func startPlanning() {
        guard let recipe else { return }
        planRequest = PlanSheetRequest(recipe: .own(recipe))
    }

    private func planned(_ result: PlanSheetResult) {
        guard case .saved(let response) = result else { return }
        withAnimation { plannedMessage = response.summary }
        AccessibilityNotification.Announcement(response.summary).post()
    }

    private func startGlutenFreeSuggestion() {
        Task { await suggestGlutenFree() }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            let result: RecipeDetail = try await api.get("api/recipes/\(recipeID)")
            recipe = result
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func suggestGlutenFree() async {
        guard let api = session.api else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let result: GlutenSuggestResult = try await api.post("api/recipe/\(recipeID)/gluten-suggest")
            guard result.ok else {
                message = result.error ?? "Er kwam geen voorstel. Probeer het later nog eens."
                return
            }
            await load()
            message = "Voorstel opgeslagen."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Ingrediënt als checklist-rij met AH-koppelstatus.
struct IngredientRow: View {
    let ingredient: Ingredient

    private var isPantry: Bool { ingredient.pantry == true }
    private var matched: Bool { !(ingredient.product ?? "").isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: matched ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(matched ? Color.misoBlue : Color.secondary)
                .padding(2)
                .background(matched ? Color.misoMint : Color.clear, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.text).opacity(ingredient.skip || isPantry ? 0.55 : 1)
                if ingredient.gluten {
                    Text("Bevat gluten → \(ingredient.gfSearch)\(ingredient.gfProduct.map { " (\($0))" } ?? "")")
                        .font(.caption).foregroundStyle(Color.misoBlue)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.misoOrange.opacity(0.3), in: Capsule())
                }
                if isPantry {
                    Text("Heb je al (basis)").font(.caption).foregroundStyle(.secondary)
                } else if matched, let product = ingredient.product {
                    HStack(spacing: 4) {
                        Text(product)
                        if let size = ingredient.unitSize, !size.isEmpty { Text("· \(size)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else if !ingredient.skip {
                    Text("Nog niet gekoppeld").misoChip(.misoLilac)
                }
            }
            Spacer(minLength: 0)
            if let q = ingredient.quantity, !q.isEmpty, !isPantry {
                Text("\(q)×").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
