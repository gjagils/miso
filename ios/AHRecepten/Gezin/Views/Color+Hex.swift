import SwiftUI

extension Color {
    /// "#RRGGBB" → kleur; ongeldig → Miso-oranje.
    init(hex: String) {
        let rgb = Self.rgb(hex) ?? (1, 138 / 255, 0)
        self.init(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let clean = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

extension Color {
    /// Lichte achtergrond: donkere tekst erop (contrast).
    var prefersDarkText: Bool {
        guard let c = UIColor(self).cgColor.components, c.count >= 3 else { return true }
        return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] > 0.6
    }
}
