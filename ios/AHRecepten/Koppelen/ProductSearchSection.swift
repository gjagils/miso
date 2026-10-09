import SwiftUI

/// Zoekveld en resultaten om een AH-product te kiezen. Zoekt zodra je even stopt met typen.
struct ProductSearchSection: View {
    @Environment(Session.self) private var session
    @Bindable var model: ProductSearchModel
    /// Product dat nu gekoppeld is (krijgt een vinkje).
    var selectedID: Int?
    var disabled = false
    let onPick: (AHProduct) -> Void

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Zoek bij AH", text: $model.query, prompt: Text("Bijv. gele paprika"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(searchNow)
                if model.searching { ProgressView() }
            }
            .frame(minHeight: 44)

            if let errorText = model.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Color.misoBlue)
            } else if !model.searching && model.results.isEmpty && !model.searchedQuery.isEmpty {
                Text("Niets gevonden voor “\(model.searchedQuery)”. Probeer een ander woord.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ForEach(model.results) { product in
                Button {
                    onPick(product)
                } label: {
                    ProductResultRow(product: product, selected: product.id == selectedID)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityHint("Koppelt dit product")
            }
        } header: {
            Text("Kies een AH-product").misoSectionHeader()
        }
        .misoRow()
        .task(id: model.query) {
            // Even wachten tot je klaar bent met typen.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let api = session.api else { return }
            await model.search(api: api)
        }
    }

    private func searchNow() {
        guard let api = session.api else { return }
        Task { await model.search(api: api) }
    }
}
