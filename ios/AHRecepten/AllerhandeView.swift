import SwiftUI

/// Zoek recepten van Albert Heijn (Allerhande) en zet ze in je eigen bibliotheek.
struct AllerhandeView: View {
    @Environment(Session.self) private var session
    @State private var query = ""
    @State private var results: [AHRecipeHit] = []
    @State private var searching = false
    @State private var adding: Int?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorText { ErrorStateView(message: errorText).listRowBackground(Color.clear) }
                if searching { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
                ForEach(results) { hit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title).font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.misoBlue)
                            if !hit.servings.isEmpty {
                                Text(hit.servings).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if hit.saved {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.misoBlue)
                                .padding(6).background(Color.misoMint, in: Circle())
                                .accessibilityLabel("Opgeslagen")
                        } else if adding == hit.id {
                            ProgressView()
                        } else {
                            Button("Toevoegen") { Task { await add(hit) } }
                                .buttonStyle(.misoPrimary)
                                .fixedSize()
                        }
                    }
                    .misoRow()
                }
                if results.isEmpty && !searching && errorText == nil {
                    EmptyStateView(pose: "shopping-cart", title: "Zin in iets van Albert Heijn?",
                                   message: "Zoek bijvoorbeeld op \"glutenvrije pasta\" of \"stamppot\".")
                        .listRowBackground(Color.clear)
                }
            }
            .misoScreen()
            .navigationTitle("AH-recepten")
            .searchable(text: $query, prompt: "Zoek in Allerhande")
            .onSubmit(of: .search) { Task { await search() } }
        }
    }

    @MainActor
    private func search() async {
        guard let api = session.api, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        errorText = nil
        defer { searching = false }
        do {
            let result: AHSearchResponse = try await api.get(
                "api/allerhande/search", query: [URLQueryItem(name: "q", value: query)]
            )
            results = result.results
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func add(_ hit: AHRecipeHit) async {
        guard let api = session.api else { return }
        adding = hit.id
        defer { adding = nil }
        do {
            let result: AddResult = try await api.post("api/allerhande/add", form: ["recipe_id": String(hit.id)])
            if result.ok, let index = results.firstIndex(where: { $0.id == hit.id }) {
                results[index].saved = true
            } else if !result.ok {
                errorText = result.error
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
