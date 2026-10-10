import SwiftUI

/// Grote letters, scherm blijft aan; tik op een stap of ingrediënt om af te vinken.
struct CookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    let recipe: RecipeDetail
    @State private var checked: Set<Int> = []
    @State private var done: Set<Int> = []
    /// "Gekookt" is al gemeld (na de helft van de stappen, of via Lekker?).
    @State private var cookedSent = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MascotView(pose: "chef", size: 72)
                        Text("Veel kookplezier! Tik om af te vinken.").font(.misoHeadline).foregroundStyle(Color.misoBlue)
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
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        Button {
                            toggle(&checked, index)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(index) ? Color.misoOrange : Color.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(ingredient.text)
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
                    TasteFeedbackSection(recipeID: recipe.id, favorite: recipe.isFavorite, onRated: rated)
                }
                .misoRow()
            }
            .misoScreen()
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar", action: close).font(.misoButton) }
            }
        }
        .onAppear { setScreenAlwaysOn(true) }
        .onDisappear { setScreenAlwaysOn(false) }
    }

    private func close() {
        dismiss()
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
    private func rated() {
        cookedSent = true
    }

    private func setScreenAlwaysOn(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    private func toggle(_ set: inout Set<Int>, _ value: Int) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}
