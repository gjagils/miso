import SwiftUI

/// Blok "Koken met wat er is" in het weekmenu: eigen recepten die grotendeels kunnen van vriezer en recente boodschappen.
/// Pure weergave; `WeekInsightsModel` laadt de voorstellen. Verdwijnt als er niets past.
struct CookWithSection: View {
    let suggestions: [CookWithSuggestion]
    let onOpen: (CookWithSuggestion) -> Void
    let onPlan: (CookWithSuggestion) -> Void

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                Section {
                    Text("Recepten van jullie zelf die grotendeels kunnen van wat in de vriezer ligt en wat jullie de laatste dagen kochten.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(suggestions) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            Button { onOpen(s) } label: {
                                Text(s.name).font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoBlue)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Text(s.detail).font(.misoCaption).foregroundStyle(.secondary)
                            Text("Heb je al: \(s.haveText)").font(.misoCaption).foregroundStyle(.secondary)
                            Button("Plan in") { onPlan(s) }
                                .buttonStyle(.misoSecondary)
                        }
                        .accessibilityElement(children: .contain)
                    }
                } header: {
                    Text("Koken met wat er is").misoSectionHeader()
                }
                .misoRow()
            }
        }
    }
}
