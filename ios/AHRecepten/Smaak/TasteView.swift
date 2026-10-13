import SwiftUI

/// Smaak per persoon: wat iemand niet lust of heel lekker vindt. Het weekvoorstel houdt er rekening mee.
struct TasteView: View {
    @Environment(Session.self) private var session
    @State private var model = TasteModel()

    var body: some View {
        List {
            if !model.suggestions.isEmpty {
                Section {
                    ForEach(model.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(suggestion.name) lust waarschijnlijk geen \(suggestion.term)")
                                .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Color.misoBlue)
                            Text(suggestion.detail).font(.misoCaption).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Button("Ja, klopt") { confirm(suggestion) }.buttonStyle(.misoPrimary)
                                Button("Nee") { dismiss(suggestion) }.buttonStyle(.misoSecondary)
                            }
                            .disabled(model.busy)
                        }
                        .accessibilityElement(children: .contain)
                    }
                } header: { Text("Klopt dit?").misoSectionHeader() } footer: {
                    Text("Op basis van wat jullie na het eten 👎 gaven.")
                }
                .misoRow()
            }
            ForEach(model.members) { member in
                Section {
                    ForEach(member.preferences) { preference in
                        HStack {
                            Text("\(preference.kind.chipText) \(preference.term)").foregroundStyle(Color.misoBlue)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .swipeActions(edge: .trailing) {
                            Button("Weg", systemImage: "trash", role: .destructive) { remove(preference) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    AddTasteRow(model: model, memberID: member.id)
                } header: { Text(member.name).misoSectionHeader() }
                .misoRow()
            }
            if let errorText = model.errorText {
                Section { Text(errorText).font(.callout) }.misoRow()
            }
            if model.loaded && model.members.isEmpty && model.errorText == nil {
                Section { Text("Nog geen gezinsleden. Zet ze eerst bij Gezinsleden.").foregroundStyle(.secondary) }.misoRow()
            }
        }
        .misoScreen()
        .navigationTitle("Smaak per persoon")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        guard let api = session.api else { return }
        await model.load(api: api)
    }

    private func confirm(_ s: TasteSuggestion) {
        guard let api = session.api else { return }
        Task { await model.confirm(s, api: api) }
    }

    private func dismiss(_ s: TasteSuggestion) {
        guard let api = session.api else { return }
        Task { await model.dismiss(s, api: api) }
    }

    private func remove(_ p: TastePreference) {
        guard let api = session.api else { return }
        Task { await model.remove(p, api: api) }
    }
}

/// Rij om iets toe te voegen: soort, ingrediënt en een knop.
private struct AddTasteRow: View {
    @Environment(Session.self) private var session
    let model: TasteModel
    let memberID: String
    @State private var kind: TasteKind = .dislike
    @State private var term = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("Soort", selection: $kind) {
                ForEach(TasteKind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("bijv. paprika", text: $term)
                .submitLabel(.done)
                .onSubmit(add)
            Button("Erbij", action: add)
                .font(.misoButton).foregroundStyle(Color.misoBlue)
                .disabled(term.trimmingCharacters(in: .whitespaces).count < 2 || model.busy)
        }
        .frame(minHeight: 44)
    }

    private func add() {
        guard let api = session.api else { return }
        Task {
            if await model.add(memberID: memberID, term: term, kind: kind, api: api) { term = "" }
        }
    }
}
