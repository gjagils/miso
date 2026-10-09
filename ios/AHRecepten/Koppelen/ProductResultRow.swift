import SwiftUI

/// AH-product in een zoekresultaat: foto, naam, merk en verpakking, prijs.
struct ProductResultRow: View {
    @Environment(Session.self) private var session
    let product: AHProduct
    var selected = false

    private var details: String {
        [product.brand, product.unitSize].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = session.api?.imageURL(product.imageUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { Color.misoLilac.opacity(0.4) }
                    }
                } else {
                    Color.misoLilac.opacity(0.4)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if product.organic { Text("bio").misoChip(.misoMint) }
                    if !product.available { Text("niet leverbaar").misoChip(.misoOrange) }
                }
            }
            Spacer(minLength: 0)
            if !product.priceText.isEmpty {
                Text(product.priceText)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
            }
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.misoBlue)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
