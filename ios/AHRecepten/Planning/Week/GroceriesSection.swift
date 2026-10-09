import SwiftUI

/// Boodschappen van de week: statusregel en één knop "Zet N nieuwe producten op je AH-lijstje".
/// Er wordt nooit iets besteld.
struct GroceriesSection: View {
    let status: WeekStatus
    let pushing: Bool
    let result: (ok: Bool, text: String)?
    let onPush: () -> Void
    @State private var showMissing = false
    @State private var showUnmatched = false

    private var count: Int { status.newCount }
    private var nothing: Bool { status.needed == 0 && status.unmatched.isEmpty }

    private var statusLine: String {
        if nothing { return "Nog niets dat gekocht moet worden deze week." }
        if count == 0 { return "Alle \(plural(status.needed, "product staat", "producten staan")) op je AH-lijstje" }
        if (status.onList ?? 0) > 0 { return "\(plural(count, "wijziging", "wijzigingen")) nog niet op je lijstje" }
        return "\(plural(count, "product", "producten")) nog niet op je lijstje"
    }

    private var buttonTitle: String {
        count > 0 ? "Zet \(count) \(count == 1 ? "nieuw product" : "nieuwe producten") op je AH-lijstje" : "Je lijstje is bij"
    }

    var body: some View {
        Section {
            Label(statusLine, systemImage: count == 0 && !nothing ? "checkmark.circle.fill" : "cart")
                .foregroundStyle(Color.misoBlue)
                .accessibilityAddTraits(.updatesFrequently)
            if !nothing {
                Button(action: onPush) {
                    if pushing { ProgressView().tint(Color.misoInk) } else { Text(buttonTitle) }
                }
                .buttonStyle(.misoPrimary)
                .disabled(count == 0 || pushing)
            }
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Color.misoBlue)
            }
            if count > 0 && !status.missing.isEmpty {
                DisclosureGroup("Wat moet er nog op?", isExpanded: $showMissing) {
                    ForEach(status.missing) { item in
                        Text("\(item.quantity)× \(item.name)").font(.callout)
                    }
                }
                .tint(Color.misoBlue)
            }
            if !status.unmatched.isEmpty {
                DisclosureGroup(isExpanded: $showUnmatched) {
                    ForEach(status.unmatched, id: \.self) { Text($0).font(.callout) }
                    NavigationLink(value: PlanRoute.missing) {
                        Label("Kies producten bij Ontbrekend", systemImage: "cart.badge.questionmark")
                            .font(.misoButton)
                            .foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                    Text("Kies daar een AH-product of zet ze op niet nodig. Dat kan ook per recept: tik op een ingrediënt.")
                        .font(.caption).foregroundStyle(.secondary)
                } label: {
                    Text("\(plural(status.unmatched.count, "ingrediënt", "ingrediënten")) zonder AH-product")
                }
                .tint(Color.misoBlue)
            }
        } header: {
            Text("Boodschappen").misoSectionHeader()
        }
        .misoRow()
    }
}
