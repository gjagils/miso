import SwiftUI

/// Licht/donker voor alleen deze app, los van de instelling van de telefoon.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Zoals telefoon"
        case .light: "Licht"
        case .dark: "Donker"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
