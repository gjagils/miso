import SwiftUI

/// Extra boodschappen bij een voorraad-dag ("+ spaghetti → AH Spaghetti").
struct PlanExtrasList: View {
    let extras: [PlanExtra]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(extras, id: \.self) { extra in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "cart").font(.caption2).accessibilityHidden(true)
                    if let product = extra.product, !product.isEmpty {
                        Text("\(extra.text) · \(product)")
                    } else {
                        Text(extra.text)
                    }
                }
                .font(.misoCaption)
                .foregroundStyle(Color.misoBlue)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Erbij kopen: \(extras.map(\.text).formatted())")
    }
}
