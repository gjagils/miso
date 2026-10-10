import SwiftUI

/// Ontbrekend: ingrediënten zonder AH-product over alle recepten, gegroepeerd op zoekterm.
/// Per groep kies je een product of zet je hem op "Niet nodig"; de groep verdwijnt dan uit de lijst.
struct MissingView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    /// Alleen de recepten van deze week (na "Zet in weekmenu"); nil = alles.
    var week: String?
    @State private var model = MissingModel()
    @State private var selected: MissingGroup?

    var body: some View {
        List {
            if let errorText = model.errorText, selected == nil {
                ErrorBanner(message: errorText, onDismiss: dismissError)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if let totals = model.totals {
                Section {
                    CoverageHeader(totals: totals, openLines: model.lineCount)
                }
                .misoRow()
            }
            if !model.loaded {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if model.groups.isEmpty && model.totals != nil {
                EmptyStateView(pose: "celebrate", title: "Alles gekoppeld",
                               message: "Elk ingrediënt heeft een AH-product of staat op niet nodig.")
                    .listRowBackground(Color.clear)
            } else if !model.groups.isEmpty {
                Section {
                    ForEach(model.groups) { group in
                        Button {
                            open(group)
                        } label: {
                            MissingGroupRow(group: group, busy: model.busyTerm == group.term)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Kies een AH-product of zet op niet nodig")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Niet nodig", systemImage: "cart.badge.minus") { skip(group) }
                                .tint(Color.misoBlue)
                        }
                    }
                } header: {
                    Text("Kies per ingrediënt").misoSectionHeader()
                } footer: {
                    Text("Tik om een AH-product te kiezen. Veeg naar links voor “Niet nodig”.")
                }
                .misoRow()
            }
        }
        .misoScreen()
        .animation(.default, value: model.groups)
        .navigationTitle(week == nil ? "Ontbrekend" : "Ontbrekend deze week")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selected) { group in
            MissingGroupSheet(group: group, model: model, onDone: changed)
        }
    }

    private func dismissError() {
        withAnimation { model.errorText = nil }
    }

    private func load() async {
        guard let api = session.api else { return }
        model.week = week
        await model.load(api: api)
    }

    private func open(_ group: MissingGroup) {
        model.errorText = nil
        selected = group
    }

    private func skip(_ group: MissingGroup) {
        guard let api = session.api else { return }
        Task {
            if await model.assign(group, product: nil, api: api) {
                changed()
                AccessibilityNotification.Announcement("\(group.term) staat op niet nodig").post()
            }
        }
    }

    private func changed() {
        router.recipesChanged()
    }
}
