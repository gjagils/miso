import Foundation
import Observation

/// Server address and login token, stored on the device.
///
/// Staat in de App Group, zodat de deel-extensie ("Deel naar Miso") dezelfde login gebruikt.
@Observable
final class Session {
    static let appGroup = "group.nl.gerdjan.ahrecepten"

    /// Gedeelde opslag (app + extensie). Valt terug op standard als de App Group niet beschikbaar is.
    static let defaults: UserDefaults = {
        guard let shared = UserDefaults(suiteName: appGroup) else { return .standard }
        // Eenmalige migratie: oudere versies bewaarden de login in UserDefaults.standard.
        if shared.string(forKey: "serverURL") == nil, let old = UserDefaults.standard.string(forKey: "serverURL") {
            shared.set(old, forKey: "serverURL")
            shared.set(UserDefaults.standard.string(forKey: "token") ?? "", forKey: "token")
            shared.set(UserDefaults.standard.bool(forKey: "connected"), forKey: "connected")
        }
        return shared
    }()

    var serverURL: String { didSet { Self.defaults.set(serverURL, forKey: "serverURL") } }
    var token: String { didSet { Self.defaults.set(token, forKey: "token") } }
    var connected: Bool { didSet { Self.defaults.set(connected, forKey: "connected") } }

    init() {
        let defaults = Self.defaults
        serverURL = defaults.string(forKey: "serverURL") ?? ""
        token = defaults.string(forKey: "token") ?? ""
        connected = defaults.bool(forKey: "connected")
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
}
