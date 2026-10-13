import SwiftUI

/// Weeksjablonen: bewaar de week die je nu ziet en zet hem met één tik op een andere week terug.
struct TemplatesView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(FamilyModel.self) private var family
    /// De week (maandag) die nu in het weekmenu staat: bewaren neemt deze, terugzetten vult deze.
    let week: String
    /// Staat er al iets (recept of voorraad) in deze week? Dan vragen we wat er met bezette dagen moet.
    let weekHasEntries: Bool
    @State private var model = TemplatesModel()
    @State private var chosen: WeekTemplate?
    @State private var asking = false
    @State private var pendingDelete: WeekTemplate?
    @State private var confirmingDelete = false

    var body: some View {
        @Bindable var model = model
        List {
            if let errorText = model.errorText {
                ErrorBanner(message: errorText, onDismiss: { withAnimation { model.errorText = nil } })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if let message = model.message {
                Text(message).font(.misoBody).foregroundStyle(Color.misoBlue)
                    .accessibilityAddTraits(.updatesFrequently)
                    .listRowBackground(Color.clear)
            }
            Section {
                if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.templates.isEmpty {
                    EmptyStateView(pose: "idea", title: "Nog geen sjablonen",
                                   message: "Bewaar een week die goed werkt, dan zet je hem zo weer neer.", size: 100)
                }
                ForEach(model.templates) { template in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.name).font(.misoButton).foregroundStyle(Color.misoInk)
                        Text(template.summary).font(.misoBody).foregroundStyle(.secondary)
                        if family.isParent {
                            Button("Zet op deze week") { use(template) }
                                .buttonStyle(.misoSecondary)
                                .disabled(model.busy)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        if family.isParent {
                            Button("Weg", systemImage: "trash", role: .destructive) { askDelete(template) }
                        }
                    }
                }
            }
            .misoRow()

            if family.isParent {
                Section {
                    TextField("Naam, bijv. Standaardweek", text: $model.newName)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Naam van het sjabloon")
                    Button(action: save) {
                        if model.busy { ProgressView().tint(Color.misoInk) } else { Text("Bewaar deze week") }
                    }
                    .buttonStyle(.misoPrimary)
                    .disabled(!model.canSave)
                } header: {
                    Text("Deze week bewaren").misoSectionHeader()
                }
                .misoRow()
            }
        }
        .misoScreen()
        .navigationTitle("Week als sjabloon")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Er staat al iets in deze week", isPresented: $asking, titleVisibility: .visible,
                            presenting: chosen) { template in
            Button("Alleen lege dagen vullen") { apply(template, replace: false) }
            Button("Bezette dagen vervangen", role: .destructive) { apply(template, replace: true) }
            Button("Annuleer", role: .cancel) {}
        }
        .confirmationDialog("\(pendingDelete?.name ?? "Dit sjabloon") weggooien?",
                            isPresented: $confirmingDelete, titleVisibility: .visible, presenting: pendingDelete) { template in
            Button("Weggooien", role: .destructive) { remove(template) }
            Button("Annuleer", role: .cancel) {}
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        await model.load(api: api)
    }

    private func save() {
        guard let api = session.api, model.canSave else { return }
        Task { await model.save(week: week, api: api) }
    }

    private func use(_ template: WeekTemplate) {
        if weekHasEntries {
            chosen = template
            asking = true
        } else {
            apply(template, replace: false)
        }
    }

    private func apply(_ template: WeekTemplate, replace: Bool) {
        guard let api = session.api else { return }
        Task {
            if await model.apply(template, week: week, replace: replace, api: api) {
                router.planChanged()
                await OrderReminderScheduler.refresh(api: api)
            }
        }
    }

    private func askDelete(_ template: WeekTemplate) {
        pendingDelete = template
        confirmingDelete = true
    }

    private func remove(_ template: WeekTemplate) {
        guard let api = session.api else { return }
        Task { await model.remove(template, api: api) }
    }
}
