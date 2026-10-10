import SwiftUI

/// "Lekker?" onderaan de kookmodus: één tik op 👍 of 👎; Miso stelt het daarna vaker of minder vaak voor.
struct TasteFeedbackSection: View {
    @Environment(Session.self) private var session
    let recipeID: Int
    @State private var sent: TasteRating?
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MascotView(pose: sent == .down ? "okay" : "taste", size: 56)
                Text("Lekker?")
                    .font(.misoTitle2)
                    .foregroundStyle(Color.misoBlue)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 12) {
                button(.up, title: "👍 Lekker", accessibility: "Lekker")
                button(.down, title: "👎 Niet zo", accessibility: "Niet zo lekker")
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color.misoBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    private func button(_ rating: TasteRating, title: String, accessibility: String) -> some View {
        Button {
            send(rating)
        } label: {
            Text(title)
        }
        .buttonStyle(.misoSecondary)
        .disabled(sent != nil || sending)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(sent == rating ? .isSelected : [])
    }

    private func send(_ rating: TasteRating) {
        guard let api = session.api, sent == nil, !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                let result = try await api.sendFeedback(recipeID, rating: rating)
                guard result.ok else { throw APIError(message: "Opslaan mislukt.") }
                sent = rating
                message = rating == .up ? "Genoteerd: lekker! Miso stelt dit vaker voor."
                                        : "Genoteerd. Miso stelt dit minder vaak voor."
            } catch {
                message = "Opslaan mislukt. \(error.localizedDescription)"
            }
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }
}
