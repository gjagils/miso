import SwiftUI

/// Product kiezen voor één zoekterm in Ontbrekend (geldt voor alle regels), of "Niet nodig".
struct MissingGroupSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let group: MissingGroup
    let model: MissingModel
    let onDone: () -> Void

    @State private var search: ProductSearchModel

    init(group: MissingGroup, model: MissingModel, onDone: @escaping () -> Void) {
        self.group = group
        self.model = model
        self.onDone = onDone
        _search = State(initialValue: ProductSearchModel(query: group.term))
    }

    private var busy: Bool { model.busyTerm != nil }

    var body: some View {
        NavigationStack {
            List {
                if let errorText = model.errorText {
                    ErrorBanner(message: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                Section {
                    ForEach(group.lines, id: \.self) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                            Text(line.recipe).font(.caption).foregroundStyle(Color.misoOrange)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Button(action: skip) {
                        if busy { ProgressView() } else { Label("Niet nodig", systemImage: "cart.badge.minus") }
                    }
                    .buttonStyle(.misoSecondary)
                    .disabled(busy)
                    .accessibilityHint("Deze regels komen niet meer in je boodschappen")
                } header: {
                    Text(group.term).misoSectionHeader()
                } footer: {
                    Text("Je keuze geldt voor alle regels hierboven, en Miso onthoudt het product voor de volgende keer.")
                }
                .misoRow()

                ProductSearchSection(model: search, disabled: busy, onPick: choose)
            }
            .misoScreen()
            .navigationTitle("Kies product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", action: close)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func close() {
        dismiss()
    }

    private func skip() {
        submit(nil)
    }

    private func choose(_ product: AHProduct) {
        submit(product)
    }

    private func submit(_ product: AHProduct?) {
        guard let api = session.api else { return }
        Task {
            if await model.assign(group, product: product, api: api) {
                onDone()
                dismiss()
            }
        }
    }
}
