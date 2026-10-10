import SwiftUI

/// Resultaat van "Zet in weekmenu en op mijn AH-lijstje", met Miso: dagen, producten, wat niet lukte,
/// en ingrediënten zonder AH-product (naar Ontbrekend).
struct ApplyResultCard: View {
    let outcome: PlannenModel.ApplyOutcome
    let week: String
    let onOpenSettings: () -> Void
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
                if outcome.unmatched > 0 {
                    NavigationLink {
                        MissingView(week: week)
                    } label: {
                        Label("\(plural(outcome.unmatched, "ingrediënt heeft", "ingrediënten hebben")) nog geen AH-product: kies ze",
                              systemImage: "cart.badge.questionmark")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoInk)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if outcome.listFailed {
                    Button(action: onOpenSettings) {
                        Text("Is AH nog niet gekoppeld? Dat doe je bij Meer → Albert Heijn.")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoInk)
                            .underline()
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: WeekmenuRoute(week: week)) {
                    Label("Bekijk het weekmenu", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.misoSecondary)
                Button("Klaar", action: onDone)
                    .buttonStyle(.misoPrimary)
            }
        }
        .padding(16)
        .background(outcome.success ? Color.misoMint : Color.misoOrange.opacity(0.35), in: .rect(cornerRadius: 20))
    }
}
