import SwiftUI

/// Voorstel van Miso met "Zet deze in het weekmenu".
struct SuggestionList: View {
    let suggestions: [MenuSuggestion]
    let applying: Bool
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(KiezenDates.label(item.date)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(item.name).font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.misoBlue)
                    if let chips = item.profiel?.chips, !chips.isEmpty {
                        Text(chips.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button(action: onApply) {
                if applying { ProgressView().tint(Color.misoInk) } else { Text("Zet deze in het weekmenu") }
            }
            .buttonStyle(.misoPrimary)
            .disabled(applying)
            Button("Liever niet", action: onDismiss)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(applying)
        }
        .padding(12)
        .background(Color.misoCream, in: .rect(cornerRadius: 14))
    }
}
