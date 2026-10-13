import SwiftUI

/// Blok "Waarschijnlijk op" onder Boodschappen. Verdwijnt als er niets aan de beurt is.
struct ReplenishSection: View {
    @Environment(Session.self) private var session
    let week: String
    @State private var model = ReplenishModel()

    var body: some View {
        Group {
            if !model.items.isEmpty {
                Section {
                    Text("Op basis van hoe vaak jullie dit kopen. Zet het op je lijstje, of zeg dat je het nog hebt.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(model.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoBlue)
                                if item.basis { Text("basis").misoChip(.misoMint) }
                            }
                            Text("\(item.whenText) · elke \(item.intervalDays) dagen")
                                .font(.misoCaption).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Button("Op het lijstje") { add(item) }
                                    .buttonStyle(.misoPrimary)
                                Button("Hebben we nog") { have(item) }
                                    .buttonStyle(.misoSecondary)
                            }
                            .disabled(model.busyID != nil)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    if let message = model.message {
                        Text(message).font(.callout).foregroundStyle(Color.misoBlue)
                    }
                } header: {
                    Text("Waarschijnlijk op").misoSectionHeader()
                }
                .misoRow()
            }
        }
        .task(id: week) {
            guard let api = session.api else { return }
            await model.load(week: week, api: api)
        }
    }

    private func add(_ item: ReplenishItem) {
        guard let api = session.api else { return }
        Task { await model.addToList(item, week: week, api: api) }
    }

    private func have(_ item: ReplenishItem) {
        guard let api = session.api else { return }
        Task { await model.haveStill(item, week: week, api: api) }
    }
}
