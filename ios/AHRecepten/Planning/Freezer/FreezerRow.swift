import SwiftUI

/// Vriezer-item met porties, "Plan in" en "−1".
struct FreezerRow: View {
    let item: FreezerItem
    let onPlan: () -> Void
    let onDecrement: () -> Void

    private var detail: String {
        var text = plural(item.portions, "portie", "porties")
        if let added = item.addedOn, KiezenDates.parse(added) != nil { text += " · sinds \(KiezenDates.short(added))" }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                Text(detail).font(.misoCaption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Plan in", action: onPlan)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Color.misoBlue)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("\(item.name) inplannen")
            Button(action: onDecrement) {
                Text("−1")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.misoInk)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 32)
                    .background(Color.misoLilac, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Eén portie minder van \(item.name)")
        }
        .buttonStyle(.borderless)
    }
}
