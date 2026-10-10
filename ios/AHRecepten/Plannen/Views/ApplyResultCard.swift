import SwiftUI

/// Resultaat van "Zet in weekmenu en op mijn AH-lijstje", met Miso.
struct ApplyResultCard: View {
    let outcome: PlannenModel.ApplyOutcome
    let onShowWeek: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MascotView(pose: outcome.success ? "celebrate" : "surprised", size: 64)
                Text(outcome.message)
                    .font(.callout)
                    .foregroundStyle(Color.misoInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if outcome.success {
                Button("Bekijk het weekmenu", systemImage: "list.bullet.rectangle", action: onShowWeek)
                    .buttonStyle(.misoSecondary)
                Button("Klaar", action: onDone)
                    .buttonStyle(.misoPrimary)
            }
        }
        .padding(16)
        .background(outcome.success ? Color.misoMint : Color.misoOrange.opacity(0.35), in: .rect(cornerRadius: 20))
    }
}
