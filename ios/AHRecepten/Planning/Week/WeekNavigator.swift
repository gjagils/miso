import SwiftUI

/// "‹ Week van 12 okt ›"
struct WeekNavigator: View {
    let title: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Label("Vorige week", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            Spacer()
            Text(title).font(.misoHeadline).foregroundStyle(Color.misoBlue)
            Spacer()
            Button(action: onNext) {
                Label("Volgende week", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.borderless)
    }
}
