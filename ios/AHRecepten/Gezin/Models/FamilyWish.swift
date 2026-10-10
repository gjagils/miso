import Foundation

/// Wens van een gezinslid (`GET /api/wishes`): een recept ("Ik wil dit graag"), een gerecht als tekst
/// ("Zin in iets?") of iets voor de boodschappen ("koekjes").
struct FamilyWish: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    /// Naam van wie het wil ("" als onbekend).
    let member: String
    let memberId: String
    let text: String
    let recipeId: Int?
    let recipeName: String
    let imageUrl: String
    let createdOn: String
    let kind: WishKind

    enum CodingKeys: String, CodingKey { case id, member, memberId, text, recipeId, recipeName, imageUrl, createdOn, kind }

    init(id: Int, member: String = "", memberId: String = "", text: String = "", recipeId: Int? = nil,
         recipeName: String = "", imageUrl: String = "", createdOn: String = "", kind: WishKind = .eten) {
        self.id = id
        self.member = member
        self.memberId = memberId
        self.text = text
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.imageUrl = imageUrl
        self.createdOn = createdOn
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientInt(.id) ?? 0
        member = c.lenient(String.self, .member) ?? ""
        memberId = c.lenient(String.self, .memberId) ?? ""
        text = c.lenient(String.self, .text) ?? ""
        recipeId = c.lenientInt(.recipeId)
        recipeName = c.lenient(String.self, .recipeName) ?? ""
        imageUrl = c.lenient(String.self, .imageUrl) ?? ""
        createdOn = c.lenient(String.self, .createdOn) ?? ""
        kind = c.lenient(WishKind.self, .kind) ?? .eten
    }

    /// Wat er gewenst is: receptnaam of de getypte tekst.
    var what: String { recipeName.isEmpty ? text : recipeName }
    var isGrocery: Bool { kind == .boodschap }
    /// Naam voor in een zin ("Iemand" als onbekend).
    var who: String { member.isEmpty ? "Iemand" : member }

    /// "Hannah wil graag: lasagne" of "🛒 Hannah wil graag mee met de boodschappen: koekjes".
    var sentence: String {
        isGrocery ? "🛒 \(who) wil graag mee met de boodschappen: \(what)" : "\(who) wil graag: \(what)"
    }

    /// In "Al doorgegeven" bij het kind: "🛒 koekjes" of "lasagne".
    var ownLine: String { isGrocery ? "🛒 \(what)" : what }

    /// Boodschappen eerst, daarna eten (zoals bij de ouders in Plannen).
    static func groceriesFirst(_ wishes: [FamilyWish]) -> [FamilyWish] {
        wishes.filter(\.isGrocery) + wishes.filter { !$0.isGrocery }
    }
}

/// Soort wens. Onbekende waarden tellen als eten.
enum WishKind: String, Codable, Sendable {
    case eten, boodschap

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = raw == "boodschap" ? .boodschap : .eten
    }
}
