import SwiftUI

/// "Gisteren: Lasagne. Lekker? 👍 👎 ♥" als dit gezinslid er nog niets over zei.
struct YesterdayCard: View {
    let title: String
    let busy: Bool
    let onRate: (TasteRating) -> Void
    let onFavorite: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Gisteren: **\(title)**. Lekker?")
                    .font(.callout)
                    .foregroundStyle(Color.misoInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Niet nu", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.misoInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
            }
            HStack(spacing: 8) {
                button("👍", label: "Lekker") { onRate(.up) }
                button("👎", label: "Liever niet") { onRate(.down) }
                button("♥", label: "Vaker maken, bij mijn favorieten", action: onFavorite)
            }
            .disabled(busy)
        }
        .padding(.leading, 14)
        .padding([.trailing, .bottom], 10)
        .background(Color.misoLilac, in: .rect(cornerRadius: 20))
    }

    private func button(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.misoCard, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
