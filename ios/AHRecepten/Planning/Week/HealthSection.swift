import SwiftUI

/// "Gezond en gevarieerd": samenvatting en signalen van `GET /api/week/health`.
struct HealthSection: View {
    let health: WeekHealth

    var body: some View {
        Section {
            Text(health.summary).font(.callout).foregroundStyle(Color.misoBlue)
            ForEach(health.signalen, id: \.self) { signal in
                Label(signal.tekst, systemImage: icon(signal.type))
                    .font(.callout)
            }
        } header: {
            Text("Gezond en gevarieerd").misoSectionHeader()
        } footer: {
            Text("Schatting per persoon door Claude (±20%), als richting. Restjes tellen als avond, niet voor variatie.")
        }
        .misoRow()
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "goed": "checkmark.circle"
        case "let_op": "exclamationmark.triangle"
        default: "lightbulb"
        }
    }
}
