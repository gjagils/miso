import SwiftUI

/// Receptfoto die de breedte van de kaart vult (4:3).
struct CardImage: View {
    @Environment(Session.self) private var session
    let path: String

    private var placeholder: some View {
        Image("Miso/hungry").resizable().scaledToFit().padding(18)
    }

    var body: some View {
        Color.misoLilac.opacity(0.5)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let url = session.api?.imageURL(path) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
