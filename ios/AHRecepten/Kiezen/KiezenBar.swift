import SwiftUI

/// Balk onderin met teller en hoofdknop.
struct KiezenBar<Leading: View>: View {
    let title: String
    var enabled = true
    var busy = false
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            Button(action: action) {
                if busy { ProgressView().tint(Color.misoInk) } else { Text(title).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .buttonStyle(.misoPrimary)
            .disabled(!enabled || busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
