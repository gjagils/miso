import SwiftUI

/// Label voor AH-maaltijdpakketten (`collection == "maaltijdpakket"`).
struct MealKitBadge: View {
    var body: some View {
        Label("Maaltijdpakket", systemImage: "shippingbox")
            .labelStyle(.titleAndIcon)
            .misoChip(.misoOrange)
    }
}
