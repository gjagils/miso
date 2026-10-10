import SwiftUI

/// "Zin in iets? Bijv. pannenkoeken" + versturen: komt bij Plannen onder "Wensen van het gezin".
struct QuickWishCard: View {
    @Binding var text: String
    let sending: Bool
    let message: String?
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Zin in iets? Bijv. pannenkoeken", text: $text)
                    .submitLabel(.send)
                    .onSubmit(onSend)
                    .misoField()
                    .accessibilityLabel("Zin in iets deze week?")
                Button("Laat het weten", action: onSend)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.misoBlue)
                    .frame(minHeight: 44)
                    .fixedSize()
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
