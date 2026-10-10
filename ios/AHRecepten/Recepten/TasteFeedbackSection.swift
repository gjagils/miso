import SwiftUI

/// "Lekker?" onderaan de kookmodus: 👍 Lekker, 👎 Liever niet (één stem per dag, om te zetten) en ♥ Vaker maken
/// (favoriet). Miso stelt het daarna vaker of minder vaak voor.
struct TasteFeedbackSection: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    let recipeID: Int
    let onRated: () -> Void
    @State private var rating: TasteRating?
    @State private var favorite: Bool
    @State private var sending = false
    @State private var message: String?

    init(recipeID: Int, favorite: Bool, onRated: @escaping () -> Void = {}) {
        self.recipeID = recipeID
        self.onRated = onRated
        _favorite = State(initialValue: favorite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MascotView(pose: rating == .down ? "okay" : "taste", size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lekker?")
                        .font(.misoTitle2)
                        .foregroundStyle(Color.misoBlue)
                        .accessibilityAddTraits(.isHeader)
                    Text("Miso leert hiervan welke recepten jullie vaker willen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                choice("👍 Lekker", on: rating == .up, accessibility: "Lekker") { send(.up) }
                choice("👎 Liever niet", on: rating == .down, accessibility: "Liever niet") { send(.down) }
            }
            choice("♥ Vaker maken", on: favorite, accessibility: "Vaker maken, bij favorieten") { toggleFavorite() }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color.misoBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .disabled(sending)
    }

    private func choice(_ title: String, on: Bool, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.caption.weight(.heavy)).accessibilityHidden(true) }
                Text(title)
            }
            .font(.misoButton)
            .foregroundStyle(on ? Color.misoInk : Color.misoBlue)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Color.misoOrange : Color.misoCard, in: Capsule())
            .overlay { Capsule().strokeBorder(on ? Color.clear : Color.misoBlue, lineWidth: 1.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func send(_ newRating: TasteRating) {
        guard let api = session.api, rating != newRating else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                let result = try await api.sendFeedback(recipeID, rating: newRating)
                guard result.ok else { throw APIError(message: "Opslaan mislukt.") }
                rating = result.rating ?? newRating
                RatedStore().mark(recipeID: recipeID, date: KiezenDates.today, member: session.memberID)
                onRated()
                message = rating == .up ? "Genoteerd: lekker! Miso stelt dit vaker voor."
                                        : "Genoteerd. Miso stelt dit minder vaak voor."
            } catch {
                message = "Opslaan mislukt. \(error.localizedDescription)"
            }
            announce()
        }
    }

    private func toggleFavorite() {
        guard let api = session.api else { return }
        let on = !favorite
        sending = true
        Task {
            defer { sending = false }
            do {
                let result = try await api.setRecipeFlags(recipeID, RecipeFlagsBody(favorite: on))
                guard result.ok else { throw APIError(message: "Opslaan mislukt.") }
                favorite = on
                router.recipesChanged()
                message = on ? "Bij jouw favorieten gezet." : "Uit jouw favorieten gehaald."
            } catch {
                message = "Opslaan mislukt. \(error.localizedDescription)"
            }
            announce()
        }
    }

    private func announce() {
        if let message { AccessibilityNotification.Announcement(message).post() }
    }
}
