import SwiftUI

/// Eén ingrediënt koppelen: AH-product kiezen, aantal verpakkingen aanpassen of op "Niet nodig" zetten.
struct IngredientSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let recipeID: Int
    let selection: IngredientSelection
    /// Nieuwe versie van de regel (na elke wijziging).
    let onSaved: (Ingredient) -> Void
    /// Het recept is intussen gewijzigd (409): opnieuw laden.
    let onConflict: () -> Void

    @State private var current: Ingredient
    @State private var quantity: Int
    @State private var search: ProductSearchModel
    @State private var saving = false
    @State private var errorText: String?

    init(recipeID: Int, selection: IngredientSelection, onSaved: @escaping (Ingredient) -> Void,
         onConflict: @escaping () -> Void) {
        self.recipeID = recipeID
        self.selection = selection
        self.onSaved = onSaved
        self.onConflict = onConflict
        _current = State(initialValue: selection.ingredient)
        _quantity = State(initialValue: selection.ingredient.packs)
        _search = State(initialValue: ProductSearchModel(query: IngredientSearchTerm.from(selection.ingredient.text)))
    }

    private var canChangeQuantity: Bool { current.isMatched && !current.skip && current.pantry != true }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    ErrorBanner(message: errorText, onDismiss: dismissError)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                Section {
                    Text(current.text).font(.misoHeadline).foregroundStyle(Color.misoBlue)
                    statusRow
                    if canChangeQuantity {
                        HStack {
                            Text("Aantal").foregroundStyle(Color.misoBlue)
                            Spacer()
                            PersonsStepper(value: quantity, range: 1...99, label: "Aantal verpakkingen",
                                           unit: ("verpakking", "verpakkingen"), onChange: setQuantity)
                        }
                        .frame(minHeight: 44)
                    }
                    if current.skip {
                        Button("Toch nodig", systemImage: "cart.badge.plus", action: unskip)
                            .buttonStyle(.misoSecondary)
                            .disabled(saving)
                    } else {
                        Button("Niet nodig", systemImage: "cart.badge.minus", action: skip)
                            .buttonStyle(.misoSecondary)
                            .disabled(saving)
                            .accessibilityHint("Dit ingrediënt komt niet meer in je boodschappen")
                    }
                } footer: {
                    Text("Je keuze geldt voor dit recept; Miso onthoudt het product ook voor andere recepten.")
                }
                .misoRow()

                ProductSearchSection(model: search, selectedID: current.productId, disabled: saving, onPick: choose)
            }
            .misoScreen()
            .navigationTitle("Ingrediënt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar", action: close)
                }
            }
            .task(id: quantity) { await saveQuantityAfterPause() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var statusRow: some View {
        if current.skip {
            Label("Niet nodig: komt niet in je boodschappen", systemImage: "cart.badge.minus")
                .font(.callout).foregroundStyle(.secondary)
        } else if current.pantry == true && !current.isMatched {
            Label("Heb je al (basis)", systemImage: "house")
                .font(.callout).foregroundStyle(.secondary)
        } else if let product = current.product, current.isMatched {
            VStack(alignment: .leading, spacing: 2) {
                Label(product, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Color.misoBlue)
                if let size = current.unitSize, !size.isEmpty {
                    Text(size).font(.caption).foregroundStyle(.secondary)
                }
                if current.manual == true {
                    Text("Door jullie gekozen").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Nog niet gekoppeld").misoChip(.misoLilac)
        }
    }

    // MARK: Acties

    private func dismissError() {
        withAnimation { errorText = nil }
    }

    private func close() {
        dismiss()
    }

    private func setQuantity(_ value: Int) {
        quantity = value
    }

    private func skip() {
        Task {
            if await save(.skip(true, text: current.text)) { dismiss() }
        }
    }

    private func unskip() {
        Task { await save(.skip(false, text: current.text)) }
    }

    private func choose(_ product: AHProduct) {
        Task {
            if await save(.choose(product, text: current.text)) { dismiss() }
        }
    }

    /// Snel tikken op − of + wordt één verzoek.
    private func saveQuantityAfterPause() async {
        guard canChangeQuantity, quantity != current.packs else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        await save(.quantity(quantity, text: current.text))
    }

    @discardableResult
    private func save(_ body: IngredientUpdateBody) async -> Bool {
        guard let api = session.api else { return false }
        saving = true
        defer { saving = false }
        do {
            let updated = try await api.updateIngredient(recipeID: recipeID, index: selection.serverIndex, body)
            current = updated
            quantity = updated.packs
            errorText = nil
            onSaved(updated)
            return true
        } catch let error as APIError where error.isConflict {
            onConflict()
            dismiss()
            return false
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}
