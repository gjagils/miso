import SwiftUI

/// Foto van het recept, of Miso voor restjes en voorraad.
struct PlanItemThumbnail: View {
    let item: PlanItem
    var size: CGFloat = 60

    var body: some View {
        switch item.kind {
        case .recipe, .other:
            RecipeImage(path: item.recipe?.imageUrl ?? "", size: size)
        case .leftover:
            mascot("pasta-again")
        case .stock:
            mascot("box")
        }
    }

    private func mascot(_ pose: String) -> some View {
        MascotView(pose: pose, size: size * 0.85)
            .frame(width: size, height: size)
            .background(Color.misoLilac.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}
