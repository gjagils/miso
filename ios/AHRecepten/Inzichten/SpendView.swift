import SwiftUI

/// Uitgaven per week, met de grootste posten en de bedragen per categorie van de gekozen week.
struct SpendView: View {
    @Environment(Session.self) private var session
    @State private var model = SpendModel()

    private func shortDate(_ iso: String) -> String { KiezenDates.short(iso) }

    var body: some View {
        List {
            if let spend = model.spend {
                if spend.tripsTotal == 0 {
                    Section {
                        EmptyStateView(pose: "shopping-cart", title: "Nog geen bestellingen of bonnen",
                                       message: "Kies Bijwerken om ze bij AH op te halen. Dat kan alleen als AH gekoppeld is.",
                                       size: 110)
                    }
                    .misoRow()
                } else {
                    Section {
                        if let avg = spend.averageWeek {
                            Text("\(Euro.format(avg)) per week gemiddeld")
                                .font(.misoHeadline).foregroundStyle(Color.misoBlue)
                        }
                        if let perDay = spend.averagePerPersonDay {
                            Text("\(Euro.format(perDay)) per persoon per dag (\(spend.householdSize) personen)")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text(plural(spend.tripsTotal, "rit", "ritten") + " in de laatste 12 weken")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .misoRow()

                    Section {
                        let maximum = max(1, spend.weeks.map(\.total).max() ?? 1)
                        ForEach(spend.weeks.reversed()) { week in
                            Button { select(week.week) } label: { weekRow(week, maximum: maximum) }
                                .buttonStyle(.plain)
                        }
                    } header: { Text("Per week").misoSectionHeader() } footer: {
                        Text("Tik op een week voor de grootste posten.")
                    }
                    .misoRow()

                    if let detail = model.detail {
                        detailSections(detail)
                    }
                }
            } else if let errorText = model.errorText {
                ErrorStateView(message: errorText).listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            if let message = model.message {
                Section { Text(message).font(.callout).foregroundStyle(Color.misoBlue) }.misoRow()
            }
        }
        .misoScreen()
        .navigationTitle("Uitgaven")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(model.syncing ? "Bezig…" : "Bijwerken", action: sync).disabled(model.syncing)
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
    }

    @ViewBuilder private func weekRow(_ week: SpendWeek, maximum: Double) -> some View {
        let selected = model.selectedWeek == week.week
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Week van \(shortDate(week.week))").font(.misoBody).foregroundStyle(Color.misoBlue)
                Spacer()
                Text(week.trips > 0 ? Euro.format(week.total) + (week.unknown > 0 ? "*" : "") : "–")
                    .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Color.misoBlue)
            }
            GeometryReader { proxy in
                Capsule().fill(selected ? Color.misoBlue : Color.misoOrange)
                    .frame(width: week.trips > 0 ? max(6, proxy.size.width * week.total / maximum) : 0)
            }
            .frame(height: 8)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week van \(shortDate(week.week)): " +
                            (week.trips > 0 ? "\(Euro.format(week.total)) in \(plural(week.trips, "rit", "ritten"))" : "geen ritten"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func detailSections(_ detail: SpendDetail) -> some View {
        Section {
            if detail.trips.isEmpty {
                Text("Geen bestellingen of bonnen in deze week.").foregroundStyle(.secondary)
            }
            ForEach(detail.trips) { trip in
                HStack {
                    Text("\(trip.source.capitalized) \(shortDate(trip.date))").foregroundStyle(Color.misoBlue)
                    Spacer()
                    Text(trip.total.map(Euro.format) ?? "–").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        } header: { Text("Week van \(shortDate(detail.week))").misoSectionHeader() }
        .misoRow()
        if !detail.top.isEmpty {
            Section {
                ForEach(detail.top) { line in
                    HStack {
                        Text(line.name).foregroundStyle(Color.misoBlue)
                        if line.bonus { Text("bonus").misoChip(.misoOrange) }
                        Spacer()
                        Text(Euro.format(line.amount)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            } header: { Text("Grootste posten").misoSectionHeader() }
            .misoRow()
        }
        if !detail.categories.isEmpty {
            Section {
                ForEach(detail.categories) { category in
                    HStack {
                        Text(category.category).foregroundStyle(Color.misoBlue)
                        Spacer()
                        Text(Euro.format(category.amount)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            } header: { Text("Per categorie").misoSectionHeader() }
            .misoRow()
        }
    }

    private func reload() async {
        guard let api = session.api else { return }
        await model.load(api: api)
    }

    private func select(_ week: String) {
        guard let api = session.api else { return }
        Task { await model.select(week, api: api) }
    }

    private func sync() {
        guard let api = session.api else { return }
        Task { await model.sync(api: api) }
    }
}
