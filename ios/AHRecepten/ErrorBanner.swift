import SwiftUI

/// Foutmelding bovenaan een scherm waar al gegevens staan, zodat die niet verdwijnen.
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.misoInk)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.misoInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onDismiss {
                Button(action: onDismiss) {
                    Label("Melding sluiten", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.callout.bold())
                        .foregroundStyle(Color.misoInk)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, onDismiss == nil ? 12 : 0)
        .padding(.trailing, onDismiss == nil ? 12 : 0)
        .background(Color.misoOrange.opacity(0.35), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}
