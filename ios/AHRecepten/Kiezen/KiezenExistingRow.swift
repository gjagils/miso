import SwiftUI

/// Wat er die dag al in het weekmenu staat (stap 2).
struct KiezenExistingRow: View {
    let item: PlanItem

    private var badge: String {
        switch item.kind {
        case .recipe, .other: "al gepland"
        case .leftover: "restjes"
        case .stock: "hebben we al"
        }
    }

    var body: some View {
        HStack {
            Text(item.title).foregroundStyle(.secondary)
            Spacer()
            Text(badge).misoChip(.misoLilac)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}
