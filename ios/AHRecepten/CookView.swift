import SwiftUI

/// Grote letters, scherm blijft aan; tik op een stap of ingrediënt om af te vinken.
struct CookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    @Environment(FamilyModel.self) private var family
    let recipe: RecipeDetail
    /// Voor hoeveel personen er gekookt wordt (uit de planning). nil = zoek op of het vandaag gepland
    /// staat, anders zoals het recept.
    var persons: Int?
    @State private var plannedPersons: Int?
    @State private var checked: Set<Int> = []
    @State private var done: Set<Int> = []
    /// "Gekookt" is al gemeld (na de helft van de stappen, of via Lekker?).
    @State private var cookedSent = false
    /// Lekker? al beantwoord in deze kookbeurt.
    @State private var rated = false
    /// Bij "Klaar" zonder Lekker?: nog even vragen (één tik).
    @State private var askingTaste = false

    private var hints: CookHints { CookHints(instructions: recipe.instructions, totalTime: recipe.totalTime) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MascotView(pose: "chef", size: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recipe.displayName).font(.misoTitle2).foregroundStyle(Color.misoBlue)
                            if recipe.showsMealKitTag { MealKitBadge() }
                            if let oven = hints.ovenText {
                                Label(oven, systemImage: "flame")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoInk)
                            }
                            if let time = hints.timeText {
                                Label(time, systemImage: "clock").font(.callout).foregroundStyle(Color.misoBlue)
                            }
                            Text("Veel kookplezier! Tik om af te vinken.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if recipe.gfMode.isActive {
                    Section {
                        GlutenFreeChip()
                        if !recipe.gfNote.isEmpty { Text(recipe.gfNote) }
                    }
                }
                Section {
                    if let note = scaleNote {
                        Text(note)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoInk)
                            .misoChip(.misoMint)
                    }
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        Button {
                            toggle(&checked, index)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(index) ? Color.misoOrange : Color.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(IngredientScaler.scaleLine(ingredient.text, factor: factor))
                                    if ingredient.gluten && recipe.gfMode.isActive && !ingredient.gfSearch.isEmpty {
                                        Text(recipe.gfMode == .replace ? "i.p.v. gluten: \(ingredient.gfSearch)" : "extra voor 1: \(ingredient.gfSearch)")
                                            .font(.callout).foregroundStyle(Color.misoBlue)
                                    }
                                }
                            }
                            .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(checked.contains(index) ? .isSelected : [])
                        .accessibilityHint(checked.contains(index) ? "Tik om het vinkje weg te halen" : "Tik om af te vinken")
                    }
                } header: { Text("Ingrediënten").misoSectionHeader() }
                .misoRow()
                Section {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                        Button {
                            toggle(&done, index)
                            markCookedIfHalfway()
                        } label: {
                            let isDone = done.contains(index)
                            HStack(alignment: .top, spacing: 10) {
                                // Klaar: vinkje i.p.v. het nummer en doorgestreepte tekst (niet alleen kleur/doorzichtigheid).
                                if isDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.misoOrange)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.system(.title3, design: .rounded).weight(.heavy))
                                        .foregroundStyle(Color.misoOrange)
                                }
                                Text(step).strikethrough(isDone)
                            }
                            .font(.title3)
                            .opacity(isDone ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Stap \(index + 1): \(step)")
                        .accessibilityValue(done.contains(index) ? "klaar" : "")
                        .accessibilityAddTraits(done.contains(index) ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint(done.contains(index) ? "Tik om als niet klaar te markeren" : "Tik om als klaar te markeren")
                    }
                } header: { Text("Bereiding").misoSectionHeader() }
                .misoRow()
                Section {
                    TasteFeedbackSection(recipeID: recipe.id,
                                         favorite: family.isMine(fans: recipe.fans, fallback: recipe.isFavorite),
                                         onRated: didRate)
                }
                .misoRow()
            }
            .misoScreen()
            .navigationTitle("Koken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar", action: finish).font(.misoButton) }
            }
            .confirmationDialog("Lekker?", isPresented: $askingTaste, titleVisibility: .visible) {
                Button("👍 Lekker") { rateAndClose(.up) }
                Button("👎 Liever niet") { rateAndClose(.down) }
                Button("Sla over", role: .cancel) { close() }
            } message: {
                Text("Miso leert hiervan wat jullie vaker willen.")
            }
        }
        .task { await findPlannedPersons() }
        .onAppear { setScreenAlwaysOn(true) }
        .onDisappear { setScreenAlwaysOn(false) }
    }

    private var effectivePersons: Int? { persons ?? plannedPersons }
    private var factor: Double { IngredientScaler.factor(persons: effectivePersons, servings: recipe.servings) }

    /// "Omgerekend voor 6 personen (recept is voor 4)"
    private var scaleNote: String? {
        guard let p = effectivePersons, IngredientScaler.needsScaling(factor) else { return nil }
        return "Omgerekend voor \(p) personen (recept is voor \(IngredientScaler.servings(recipe.servings)))"
    }

    /// Geopend vanaf het recept: staat het vandaag gepland? Dan voor dat aantal personen (zoals de web-kookmodus).
    private func findPlannedPersons() async {
        guard persons == nil, let api = session.api,
              let today = try? await api.planEntries(start: KiezenDates.today, days: 1) else { return }
        if let item = today.entries.first(where: { $0.recipeId == recipe.id && $0.kind == .recipe }) {
            let p = item.groceryPersons > 0 ? item.groceryPersons : item.persons
            plannedPersons = p > 0 ? p : nil
        }
    }

    private func close() {
        dismiss()
    }

    /// Klaar met koken (de helft van de stappen gedaan) en nog niets gezegd: één vraag, dan dicht.
    private func finish() {
        if !rated && CookProgress.isHalfway(done: done.count, steps: recipe.instructions.count) {
            askingTaste = true
        } else {
            close()
        }
    }

    private func rateAndClose(_ rating: TasteRating) {
        guard let api = session.api else { return close() }
        let member = session.memberID
        let id = recipe.id
        Task {
            if (try? await api.sendFeedback(id, rating: rating)) != nil {
                RatedStore().mark(recipeID: id, date: KiezenDates.today, member: member)
            }
        }
        close()
    }

    /// Telt pas als gekookt als minstens de helft van de stappen is afgevinkt (zoals de web-kookmodus).
    /// Eén keer per keer openen; de server telt bovendien één keer per dag. Mislukken is niet erg.
    private func markCookedIfHalfway() {
        guard !cookedSent, CookProgress.isHalfway(done: done.count, steps: recipe.instructions.count),
              let api = session.api else { return }
        cookedSent = true
        Task { _ = try? await api.markCooked(recipe.id) }
    }

    /// Lekker? telt op de server ook als gekookt.
    private func didRate() {
        cookedSent = true
        rated = true
    }

    private func setScreenAlwaysOn(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    private func toggle(_ set: inout Set<Int>, _ value: Int) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}
