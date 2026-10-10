import SwiftUI

/// "Boodschappen": hoeveel geplande gerechten klaarstaan op het AH-lijstje of in de bestelling, wat er
/// nog mist, en één knop om het ontbrekende op het lijstje te zetten. Bestelt nooit iets.
struct ListStatusCard: View {
    let status: ListStatus
    let syncing: Bool
    var checking = false
    var message: String?
    let onSync: () -> Void
    let onCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Boodschappen", systemImage: "cart")
                .font(.misoHeadline)
                .foregroundStyle(Color.misoBlue)
                .accessibilityAddTraits(.isHeader)
            if status.isChecked && !status.entries.isEmpty {
                Text(status.summary)
                    .font(.callout)
                    .foregroundStyle(Color.misoInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(status.checkedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(status.todoEntries) { entry in
                Label(entry.todoLine, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.misoBlue)
            }
            if !status.todoEntries.isEmpty {
                Button(action: onSync) {
                    if syncing {
                        HStack(spacing: 8) { ProgressView(); Text("Bezig…") }
                    } else {
                        Text("Zet ontbrekende op mijn AH-lijstje")
                    }
                }
                .buttonStyle(.misoPrimary)
                .disabled(syncing)
            }
            Button(action: onCheck) {
                if checking {
                    HStack(spacing: 8) { ProgressView(); Text("Miso kijkt bij AH…") }
                } else {
                    Label("Controleer met AH", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.misoSecondary)
            .disabled(checking || syncing)
            if let message {
                Text(message).font(.callout).foregroundStyle(Color.misoBlue)
            }
        }
        .misoCard()
    }
}

/// Klein label bij een gepland gerecht: "Boodschappen ✓" of "Nog op lijstje zetten".
struct ListStatusBadge: View {
    let entry: ListStatusEntry

    var body: some View {
        Text(entry.badge)
            .misoChip(entry.isTodo ? .misoOrange : .misoMint)
            .accessibilityLabel(entry.isTodo ? "Boodschappen nog op het lijstje zetten" : "Boodschappen staan klaar")
    }
}
