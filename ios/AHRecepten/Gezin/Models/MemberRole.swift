import Foundation

/// Rol van een gezinslid. Onbekende waarden tellen als ouder (zoals op de server).
enum MemberRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case ouder, kind

    var id: String { rawValue }
    var title: String { self == .ouder ? "Ouder" : "Kind" }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = raw == "kind" ? .kind : .ouder
    }
}
