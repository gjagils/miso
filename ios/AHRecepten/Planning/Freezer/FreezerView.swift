import SwiftUI

/// Vriezerlijst: porties bijhouden, iets erin zetten, eruit halen of inplannen.
struct FreezerView: View {
    @Environment(Session.self) private var session
    /// Week waarvoor "Plan in" dagen voorstelt (nil = vanaf vandaag).
    var week: String?
    var firstFreeDay: String?
    @State private var model = FreezerModel()
    @State private var planRequest: PlanSheetRequest?
    @State private var lastPortion: FreezerItem?
    @State private var confirmingLast = false

    var body: some View {
        @Bindable var model = model
        List {
            if let errorText = model.errorText {
                ErrorBanner(message: errorText, onDismiss: dismissError)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.items.isEmpty {
                    EmptyStateView(pose: "chill", title: "Niets in de vriezer",
                                   message: "Kook je dubbel? Kies dan \"naar de vriezer\" bij het inplannen.", size: 100)
                }
                ForEach(model.items) { item in
                    FreezerRow(item: item, onPlan: { plan(item) }, onDecrement: { decrement(item) })
                        .swipeActions(edge: .trailing) {
                            Button("Haal weg", systemImage: "trash", role: .destructive) { remove(item) }
                                .tint(.red)
                        }
                }
            }
            .misoRow()

            Section {
                TextField("Bijv. pastasaus", text: $model.newName)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Wat gaat de vriezer in?")
                HStack {
                    Text("Porties").foregroundStyle(Color.misoBlue)
                    Spacer()
                    PersonsStepper(value: model.newPortions, range: 1...50, label: "Aantal porties",
                                   unit: ("portie", "porties"), onChange: model.setNewPortions)
                }
                Button(action: add) {
                    if model.adding { ProgressView().tint(Color.misoInk) } else { Text("Erin") }
                }
                .buttonStyle(.misoPrimary)
                .disabled(!model.canAdd)
            } header: {
                Text("Iets in de vriezer zetten").misoSectionHeader()
            }
            .misoRow()
        }
        .misoScreen()
        .navigationTitle("Vriezer")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $planRequest) { request in
            PlanSheet(request: request) { _ in reload() }
        }
        .confirmationDialog("\(lastPortion?.name ?? "Dit") is dan op. Weghalen uit de vriezer?",
                            isPresented: $confirmingLast, titleVisibility: .visible, presenting: lastPortion) { item in
            Button("Weghalen", role: .destructive) { confirmDecrement(item) }
            Button("Annuleer", role: .cancel) {}
        }
    }

    // MARK: Acties

    private func dismissError() {
        withAnimation { model.errorText = nil }
    }

    private func load() async {
        guard let api = session.api else { return }
        await model.load(api: api)
    }

    private func reload() {
        Task { await load() }
    }

    private func add() {
        guard let api = session.api, model.canAdd else { return }
        Task { await model.add(api: api) }
    }

    private func plan(_ item: FreezerItem) {
        planRequest = PlanSheetRequest(showTabs: true, tab: .stock, freezerItem: item, date: firstFreeDay, start: week)
    }

    private func decrement(_ item: FreezerItem) {
        if item.portions <= 1 {
            lastPortion = item
            confirmingLast = true
        } else {
            confirmDecrement(item)
        }
    }

    private func confirmDecrement(_ item: FreezerItem) {
        guard let api = session.api else { return }
        Task { await model.decrement(item, api: api) }
    }

    private func remove(_ item: FreezerItem) {
        guard let api = session.api else { return }
        Task { await model.remove(item, api: api) }
    }
}
