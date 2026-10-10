import Foundation
import Observation

/// Wie er tikt ("Wie ben jij?"), het gezin, en of AH gekoppeld is (`GET /api/members`).
/// De keuze zelf staat in `Session.memberID` (gaat als header mee); de rol wordt hier onthouden zodat
/// een kind ook vóór het laden geen ouder-knoppen ziet.
@MainActor
@Observable
final class FamilyModel {
    private(set) var members: [Member] = []
    /// AH gekoppeld (nil = onbekend, oudere server).
    private(set) var ahConnected: Bool?
    private(set) var loaded = false
    private(set) var loading = false
    /// De server kent geen gezinsleden (oudere versie): geen "Wie ben jij?".
    private(set) var unsupported = false
    private(set) var errorText: String?
    /// "Later" op het kiesscherm: deze keer niet meer vragen.
    private(set) var skipped = false
    /// Gekozen lid (spiegel van `Session.memberID`).
    private(set) var memberID: String
    private var cachedRole: MemberRole?
    @ObservationIgnored private let defaults: UserDefaults

    private static let roleKey = "memberRole"

    init(memberID: String = "", defaults: UserDefaults = Session.defaults) {
        self.memberID = memberID
        self.defaults = defaults
        cachedRole = defaults.string(forKey: Self.roleKey).flatMap(MemberRole.init(rawValue:))
    }

    var current: Member? { members.first { $0.id == memberID } }

    /// Kinderrol: wensen doorgeven, niets wissen, verplaatsen, opruimen of bestellen.
    var isKid: Bool {
        if let current { return current.isKid }
        return !memberID.isEmpty && cachedRole == .kind
    }

    var isParent: Bool { !isKid }

    /// Kiesscherm tonen: nog niemand gekozen, of het gekozen lid bestaat niet meer.
    var needsPick: Bool {
        guard !unsupported, !skipped else { return false }
        if memberID.isEmpty { return true }
        return loaded && !members.isEmpty && current == nil
    }

    /// Mijn hartje: staat mijn initiaal bij de fans? Zonder gekozen lid: de oude gezinsfavoriet.
    func isMine(fans: [String]?, fallback: Bool) -> Bool {
        guard let me = current, let fans else { return fallback }
        return fans.contains(me.initial)
    }

    func load(api: API) async {
        loading = true
        defer { loading = false }
        do {
            apply(try await api.members())
        } catch let error as APIError where error.status == 404 {
            unsupported = true
            loaded = true
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
    }

    /// Antwoord van `GET /api/members` overnemen.
    func apply(_ result: MembersResponse) {
        members = result.members
        ahConnected = result.ahConnected
        unsupported = result.members.isEmpty
        errorText = nil
        loaded = true
        if let current { remember(role: current.role) }
    }

    /// Lid kiezen; de header gaat vanaf nu mee.
    func choose(_ member: Member, session: Session) {
        session.memberID = member.id
        memberID = member.id
        skipped = false
        remember(role: member.role)
    }

    /// Spiegel bijwerken als het id elders veranderde (bijv. na opnieuw starten).
    func sync(memberID: String) {
        self.memberID = memberID
    }

    func skip() {
        skipped = true
    }

    func replaceMembers(_ newMembers: [Member]) {
        members = newMembers
        if let current { remember(role: current.role) }
    }

    private func remember(role: MemberRole) {
        cachedRole = role
        defaults.set(role.rawValue, forKey: Self.roleKey)
    }
}
