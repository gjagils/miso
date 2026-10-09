import Foundation
import Observation

/// Serveradres en login-token, opgeslagen op het toestel.
///
/// Het serveradres staat in de App Group en het token in een gedeelde keychain-groep, zodat de
/// deel-extensie ("Deel naar Miso") dezelfde login gebruikt.
@MainActor
@Observable
final class Session {
    static let appGroup = "group.nl.gerdjan.ahrecepten"
    private static let tokenKey = "token"

    /// Gedeelde opslag (app + extensie). Valt terug op standard als de App Group niet beschikbaar is.
    static let defaults: UserDefaults = {
        guard let shared = UserDefaults(suiteName: appGroup) else { return .standard }
        // Eenmalige migratie: oudere versies bewaarden de login in UserDefaults.standard.
        if shared.string(forKey: "serverURL") == nil, let old = UserDefaults.standard.string(forKey: "serverURL") {
            shared.set(old, forKey: "serverURL")
            shared.set(UserDefaults.standard.string(forKey: tokenKey) ?? "", forKey: tokenKey)
            shared.set(UserDefaults.standard.bool(forKey: "connected"), forKey: "connected")
        }
        return shared
    }()

    var serverURL: String { didSet { Self.defaults.set(serverURL, forKey: "serverURL") } }
    var token: String { didSet { Self.storeToken(token) } }
    var connected: Bool { didSet { Self.defaults.set(connected, forKey: "connected") } }
    /// Waarom de app uitlogde (bijv. verlopen sessie); het inlogscherm toont dit.
    var logoutReason: String?

    init() {
        let defaults = Self.defaults
        serverURL = defaults.string(forKey: "serverURL") ?? ""
        token = Self.loadToken()
        connected = defaults.bool(forKey: "connected")
    }

    /// Token uit de keychain. Eenmalige migratie: oudere versies bewaarden het in de App Group-defaults;
    /// dat wordt pas weggehaald als het veilig in de keychain staat, zodat je ingelogd blijft.
    private static func loadToken() -> String {
        if let token = Keychain.string(for: tokenKey) {
            defaults.removeObject(forKey: tokenKey)
            return token
        }
        guard let legacy = defaults.string(forKey: tokenKey), !legacy.isEmpty else { return "" }
        if Keychain.set(legacy, for: tokenKey) { defaults.removeObject(forKey: tokenKey) }
        return legacy
    }

    private static func storeToken(_ token: String) {
        if Keychain.set(token, for: tokenKey) {
            defaults.removeObject(forKey: tokenKey)
        } else {
            // Keychain niet beschikbaar: liever ingelogd blijven dan het token kwijtraken.
            defaults.set(token, forKey: tokenKey)
        }
    }

    var isConnected: Bool { connected && api != nil }

    var api: API? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.scheme != nil else { return nil }
        return API(baseURL: url, token: token)
    }

    func logout() {
        connected = false
        token = ""
    }

    /// De server weigert het token (401): uitloggen met een vriendelijke uitleg op het inlogscherm.
    func expire() {
        guard connected else { return }
        logoutReason = "Je bent uitgelogd, want je sessie is verlopen of de pincode is gewijzigd. Log opnieuw in."
        logout()
    }
}
