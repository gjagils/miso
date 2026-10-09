import SwiftUI

/// Receptkaart in het keuzeraster; tik om te kiezen of niet meer te kiezen.
struct PickCard: View {
    let item: PickItem
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                CardImage(path: item.imageUrl)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(Color.misoBlue)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !item.meta.isEmpty {
                        Text(item.meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }
            .background(Color.misoCard)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? Color.misoOrange : Color.misoBlue.opacity(0.08), lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.misoInk)
                        .frame(width: 32, height: 32)
                        .background(Color.misoOrange, in: Circle())
                        .overlay { Circle().stroke(Color.misoCard, lineWidth: 2) }
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: Color.misoInk.opacity(0.08), radius: 6, x: 0, y: 2)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.meta.isEmpty ? item.name : "\(item.name), \(item.meta)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? "Tik om niet meer te kiezen" : "Tik om te kiezen")
    }
}
