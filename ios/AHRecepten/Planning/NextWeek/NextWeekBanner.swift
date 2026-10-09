import SwiftUI

/// "Volgende week: 4 van 7 dagen gepland · nog 2 dagen tot zondag (besteldag)".
/// Groot met knoppen vanaf 2 dagen voor de besteldag; anders één compacte regel.
struct NextWeekBanner: View {
    let model: NextWeekModel
    let onPlan: () -> Void
    let onSuggest: () -> Void
    let onApply: () -> Void
    let onDismissSuggestions: () -> Void

    var body: some View {
        if let status = model.status {
            if model.isProminent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        MascotView(pose: "checklist", size: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tijd om volgende week te plannen")
                                .font(.misoHeadline).foregroundStyle(Color.misoBlue)
                                .accessibilityAddTraits(.isHeader)
                            Text(status.message).font(.callout).foregroundStyle(Color.misoInk)
                            PlannedDots(planned: status.plannedDays, total: status.totalDays)
                        }
                    }
                    Button("Plan volgende week", action: onPlan)
                        .buttonStyle(.misoPrimary)
                    Button(action: onSuggest) {
                        if model.suggesting { Text("Miso denkt na…") } else { Text("Laat Miso voorstellen") }
                    }
                    .buttonStyle(.misoSecondary)
                    .disabled(model.suggesting || model.applying)
                    if let suggestions = model.suggestions, !suggestions.isEmpty {
                        SuggestionList(suggestions: suggestions, applying: model.applying,
                                       onApply: onApply, onDismiss: onDismissSuggestions)
                    }
                    if let message = model.message {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .misoCard()
                .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Color.misoOrange, lineWidth: 2)
                }
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        PlannedDots(planned: status.plannedDays, total: status.totalDays)
                        Text(status.message).font(.footnote).foregroundStyle(Color.misoBlue)
                        if let message = model.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if !status.isComplete {
                        Button("Plan", action: onPlan)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.misoBlue)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Plan volgende week")
                    }
                }
                .misoCard(padding: 12)
            }
        }
    }
}
