import SwiftUI

/// "Zeg het in één zin": Claude zet de zin om naar wensen per dag. Dicteren via het toetsenbord werkt ook.
struct SentenceCard: View {
    @Binding var text: String
    let reading: Bool
    let message: String?
    var focus: FocusState<String?>.Binding
    let onSubmit: () -> Void

    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zeg het in één zin")
                .font(.misoHeadline)
                .foregroundStyle(Color.misoBlue)
                .accessibilityAddTraits(.isHeader)
            TextField("Bijv. maandag rijst, dinsdag wraps, woensdag vriezer, donderdag lasagne",
                      text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused(focus, equals: "zin")
                .submitLabel(.go)
                .onSubmit { if canSubmit { onSubmit() } }
                .misoField()
                .accessibilityLabel("Wensen in één zin")
            Button(action: onSubmit) {
                if reading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Miso leest mee…")
                    }
                } else {
                    Label("Vul de dagen in", systemImage: "text.badge.checkmark")
                }
            }
            .buttonStyle(.misoSecondary)
            .disabled(!canSubmit)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color.misoBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .misoCard()
    }
}
