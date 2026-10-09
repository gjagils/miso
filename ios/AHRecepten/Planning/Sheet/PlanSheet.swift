import SwiftUI

/// Het ene "Inplannen"-scherm: dag, personen en kook dubbel; vanuit het weekmenu ook recept zoeken of
/// "uit de vriezer / hebben we al". Gebruikt `POST /api/plan/entries` (of `PATCH` bij verplaatsen).
struct PlanSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlanSheetModel
    let onDone: (PlanSheetResult) -> Void

    init(request: PlanSheetRequest, onDone: @escaping (PlanSheetResult) -> Void) {
        _model = State(initialValue: PlanSheetModel(request: request))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.showsTabs {
                        PlanSheetTabPicker(selection: $model.tab)
                    }
                    if !model.isMove {
                        switch model.tab {
                        case .recipe: PlanRecipePanel(model: model)
                        case .stock: PlanStockPanel(model: model)
                        }
                    }
                    DayChipStrip(chips: model.chips, selected: model.date, info: model.dayInfo,
                                 onSelect: model.select, onShift: shiftWeek)
                    if model.showsPersons {
                        HStack {
                            Text("Voor hoeveel personen?").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                            Spacer()
                            PersonsStepper(value: model.persons, label: "Voor hoeveel personen?", onChange: model.setPersons)
                        }
                    }
                    if model.showsCookDouble {
                        CookDoubleSection(isOn: $model.cookDoubleOn, choice: $model.cookDoubleChoice)
                    }
                    if let errorText = model.errorText {
                        ErrorBanner(message: errorText)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.misoCream)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", action: cancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                KiezenBar(title: model.busy ?? model.submitLabel, enabled: model.date != nil,
                          busy: model.busy != nil, action: startSubmit) {
                    EmptyView()
                }
            }
            .task { await load() }
            .task(id: model.tab) { await tabChanged() }
            .task(id: model.query) { await search() }
        }
    }

    // MARK: Acties

    private func cancel() {
        dismiss()
    }

    private func shiftWeek(_ days: Int) {
        guard let api = session.api else { return }
        Task { await model.shiftWeek(days, api: api) }
    }

    private func load() async {
        guard let api = session.api else { return }
        await model.load(api: api)
    }

    private func tabChanged() async {
        guard let api = session.api else { return }
        await model.tabDidChange(api: api)
    }

    private func search() async {
        guard let api = session.api else { return }
        await model.search(api: api)
    }

    private func startSubmit() {
        guard let api = session.api else { return }
        Task {
            guard let result = await model.submit(api: api) else { return }
            onDone(result)
            dismiss()
        }
    }
}
