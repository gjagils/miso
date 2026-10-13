import SwiftUI

/// Goedkopere alternatieven voor de gekoppelde producten van een recept.
struct CheaperSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let recipeID: Int
    /// Er is een product gewisseld: het recept moet opnieuw geladen worden.
    let onChanged: () -> Void
    @State private var model = CheaperModel()

    var body: some View {
        NavigationStack {
            List {
                if model.searching && !model.searched {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Miso zoekt bij AH… dit kan even duren.").font(.callout)
                        }
                    }
                    .misoRow()
                } else if let errorText = model.errorText, model.suggestions.isEmpty {
                    Section { Text(errorText).font(.callout) }.misoRow()
                } else if model.searched && model.suggestions.isEmpty {
                    Section {
                        EmptyStateView(pose: "okay", title: "Dit is al een goede keuze",
                                       message: "Niets gevonden dat net zo goed past en merkbaar goedkoper is.", size: 110)
                    }
                    .misoRow()
                } else {
                    Section {
                        Text("Je kunt \(Euro.format(model.totalSaving)) besparen.")
                            .font(.misoHeadline).foregroundStyle(Color.misoBlue)
                    } footer: {
                        Text("Kiezen koppelt het product aan dit ingrediënt; Miso onthoudt je keuze ook voor andere recepten.")
                    }
                    .misoRow()
                    ForEach(model.suggestions) { suggestion in
                        Section {
                            row(suggestion)
                        } header: { Text(suggestion.text).misoSectionHeader() }
                        .misoRow()
                    }
                    if let errorText = model.errorText {
                        Section { Text(errorText).font(.callout) }.misoRow()
                    }
                }
            }
            .misoScreen()
            .navigationTitle("Goedkoper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() }.font(.misoButton) }
            }
            .task {
                guard let api = session.api, !model.searched else { return }
                await model.search(recipeID: recipeID, api: api)
            }
        }
    }

    @ViewBuilder private func row(_ s: CheaperSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nu: \(s.current.product.name) (\(Euro.format(s.current.cost)))")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.alternative.product.name)
                        .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Color.misoBlue)
                    Text([s.alternative.product.unitSize, Euro.format(s.alternative.cost)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.misoCaption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("scheelt \(Euro.format(s.saving))").misoChip(.misoMint)
            }
            if s.manual {
                Text("Je had dit zelf gekozen.").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                choose(s)
            } label: {
                if model.busyIndex == s.index { ProgressView().tint(Color.misoInk) } else { Text("Kies deze") }
            }
            .buttonStyle(.misoPrimary)
            .disabled(model.busyIndex != nil)
        }
        .accessibilityElement(children: .contain)
    }

    private func choose(_ suggestion: CheaperSuggestion) {
        guard let api = session.api else { return }
        Task {
            if await model.choose(suggestion, recipeID: recipeID, api: api) { onChanged() }
        }
    }
}
