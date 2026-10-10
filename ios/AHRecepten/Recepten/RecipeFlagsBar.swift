import SwiftUI

/// ♥ Favoriet, "Ken ik uit mijn hoofd" en Opruimen/Terugzetten op het recept, plus het gebruik.
struct RecipeFlagsBar: View {
    let recipe: RecipeDetail
    let busy: Bool
    /// Mijn hartje (per gezinslid).
    var favoriteOn: Bool
    /// Kind: geen "uit mijn hoofd" en geen opruimen.
    var isKid = false
    let onFavorite: () -> Void
    let onByHeart: () -> Void
    let onArchive: () -> Void

    /// "3× gekookt · 👍 2 · 👎 0" of "Nog niet gekookt met Miso".
    static func usageLine(cooked: Int?, up: Int?, down: Int?) -> String {
        let cooked = cooked ?? 0
        let first = cooked > 0 ? "\(cooked)× gekookt" : "Nog niet gekookt met Miso"
        let thumbs = (up ?? 0) > 0 || (down ?? 0) > 0 ? " · 👍 \(up ?? 0) · 👎 \(down ?? 0)" : ""
        return first + thumbs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                toggle(title: fansTitle, systemImage: favoriteOn ? "heart.fill" : "heart",
                       on: favoriteOn, action: onFavorite,
                       hint: "Miso stelt favorieten vaker voor")
                    .accessibilityLabel(fansAccessibility)
                if !isKid {
                    toggle(title: "Uit mijn hoofd", systemImage: "brain.head.profile",
                           on: recipe.isByHeart, action: onByHeart,
                           hint: "Houdt de boodschappen, zonder kookmodus")
                }
            }
            if !isKid {
                Button(action: onArchive) {
                    Label(recipe.isArchived ? "Terugzetten" : "Opruimen",
                          systemImage: recipe.isArchived ? "arrow.uturn.backward" : "archivebox")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.misoBlue)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityHint(recipe.isArchived
                    ? "Zet het recept terug in je lijsten en voorstellen"
                    : "Niet meer tonen in lijsten en voorstellen; terug te halen bij Recepten, Opgeruimd")
            }
            Text(Self.usageLine(cooked: recipe.cookedCount, up: recipe.thumbsUp, down: recipe.thumbsDown))
                .font(.misoCaption)
                .foregroundStyle(.secondary)
        }
        .disabled(busy)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Favoriet · H S"
    private var fansTitle: String {
        let fans = recipe.fans ?? []
        return fans.isEmpty ? "Favoriet" : "Favoriet · \(fans.joined(separator: " "))"
    }

    private var fansAccessibility: String {
        let fans = recipe.fans ?? []
        return fans.isEmpty ? "Favoriet" : "Favoriet, ook van \(fans.joined(separator: ", "))"
    }

    private func toggle(title: String, systemImage: String, on: Bool, action: @escaping () -> Void,
                        hint: String) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(on ? Color.misoInk : Color.misoBlue)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color.misoOrange : Color.misoCream, in: Capsule())
                .overlay { Capsule().strokeBorder(on ? Color.clear : Color.misoBlue.opacity(0.3), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(hint)
    }
}
