import SwiftUI

// MARK: - Kleuren

extension Color {
    static let misoBlue = Color("MisoBlue")
    static let misoOrange = Color("MisoOrange")
    static let misoCream = Color("MisoCream")
    static let misoMint = Color("MisoMint")
    static let misoLilac = Color("MisoLilac")
    static let misoCard = Color("MisoCard")
    /// Vaste donkerblauwe tekstkleur (ook in dark mode), voor op oranje/mint/lila vlakken.
    static let misoInk = Color(red: 14 / 255, green: 42 / 255, blue: 71 / 255)
}

// MARK: - Lettertypen (later te vervangen door Baloo 2 / Inter)

extension Font {
    static let misoLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let misoTitle = Font.system(.title, design: .rounded).weight(.heavy)
    static let misoTitle2 = Font.system(.title2, design: .rounded).weight(.bold)
    static let misoHeadline = Font.system(.headline, design: .rounded).weight(.bold)
    static let misoButton = Font.system(.body, design: .rounded).weight(.bold)
    static let misoBody = Font.system(.body)
    static let misoCaption = Font.system(.caption)
}

// MARK: - Knoppen

struct MisoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.misoButton)
            .foregroundStyle(Color.misoInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.misoOrange.opacity(enabled ? 1 : 0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct MisoSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.misoButton)
            .foregroundStyle(Color.misoBlue)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.misoCard, in: Capsule())
            .overlay(Capsule().stroke(Color.misoBlue, lineWidth: 1.5))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension ButtonStyle where Self == MisoPrimaryButtonStyle {
    static var misoPrimary: MisoPrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == MisoSecondaryButtonStyle {
    static var misoSecondary: MisoSecondaryButtonStyle { .init() }
}

// MARK: - Kaarten, chips, koppen

struct MisoCardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.misoCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.misoInk.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}

struct MisoChipModifier: ViewModifier {
    var fill: Color = .misoLilac
    func body(content: Content) -> some View {
        content
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(fill == .misoLilac || fill == .misoMint ? Color.misoBlue : Color.misoInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}

extension View {
    func misoCard(padding: CGFloat = 16) -> some View { modifier(MisoCardModifier(padding: padding)) }
    func misoChip(_ fill: Color = .misoLilac) -> some View { modifier(MisoChipModifier(fill: fill)) }
    func misoSectionHeader() -> some View {
        self.font(.misoHeadline).foregroundStyle(Color.misoBlue).textCase(nil)
    }
    /// Scherm met crème achtergrond (voor List/Form én gewone schermen).
    func misoScreen() -> some View {
        self.scrollContentBackground(.hidden).background(Color.misoCream)
    }
    /// Rijen in een List/Form als kaart.
    func misoRow() -> some View {
        self.listRowBackground(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.misoCard)
        )
    }
}

/// Rij met afgeronde invoerveld-stijl.
struct MisoFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .frame(minHeight: 44)
            .background(Color.misoCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.misoBlue.opacity(0.2), lineWidth: 1))
    }
}
