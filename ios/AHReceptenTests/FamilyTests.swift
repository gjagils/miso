import Foundation
import Testing
@testable import AHRecepten

/// Gezinsleden, wensen en de kinderrol ("Wie ben jij?").
@MainActor
struct FamilyTests {
    static let members = #"""
    {"members": [
      {"id": "gerd-jan", "name": "Gerd-Jan", "role": "ouder", "initial": "G", "color": "#FF8A00"},
      {"id": "nelleke", "name": "Nelleke", "role": "ouder", "initial": "N", "color": "#0E2A47"},
      {"id": "hannah", "name": "Hannah", "role": "kind", "initial": "H", "color": "#7BC8A4"},
      {"id": "suze", "name": "Suze", "role": "iets-nieuws"}
    ], "current": {"id": "hannah", "name": "Hannah", "role": "kind", "initial": "H", "color": "#7BC8A4"},
    "ah_connected": false}
    """#

    private func decoded() throws -> MembersResponse {
        try API.decoder.decode(MembersResponse.self, from: Data(Self.members.utf8))
    }

    @Test func decodesMembers() throws {
        let r = try decoded()
        #expect(r.members.map(\.id) == ["gerd-jan", "nelleke", "hannah", "suze"])
        #expect(r.members[2].isKid)
        #expect(r.members[2].initial == "H")
        #expect(r.members[2].color == "#7BC8A4")
        // Onbekende rol telt als ouder; ontbrekende initiaal komt uit de naam.
        #expect(r.members[3].role == .ouder)
        #expect(r.members[3].initial == "S")
        #expect(r.current?.id == "hannah")
        #expect(r.ahConnected == false)
    }

    @Test func oldServerWithoutAHFlag() throws {
        let r = try API.decoder.decode(MembersResponse.self, from: Data(#"{"members": [], "current": null}"#.utf8))
        #expect(r.members.isEmpty)
        #expect(r.current == nil)
        #expect(r.ahConnected == nil)
    }

    @Test func decodesWishes() throws {
        let json = #"""
        {"wishes": [
          {"id": 3, "member": "Hannah", "member_id": "hannah", "text": "", "recipe_id": 7,
           "recipe_name": "Nasi goreng", "image_url": "/image/7", "created_on": "2026-10-10", "kind": "eten"},
          {"id": 4, "member": "Suze", "member_id": "suze", "text": "koekjes", "recipe_id": null,
           "recipe_name": "", "image_url": "", "created_on": "2026-10-10", "kind": "boodschap"},
          {"id": 5, "member": "", "member_id": "", "text": "pannenkoeken", "recipe_id": null}
        ]}
        """#
        let r = try API.decoder.decode(WishesResponse.self, from: Data(json.utf8))
        #expect(r.ok)
        #expect(r.wishes.count == 3)
        #expect(r.wishes[0].sentence == "Hannah wil graag: Nasi goreng")
        #expect(r.wishes[1].isGrocery)
        #expect(r.wishes[1].sentence == "🛒 Suze wil graag mee met de boodschappen: koekjes")
        #expect(r.wishes[1].ownLine == "🛒 koekjes")
        #expect(r.wishes[2].kind == .eten)
        #expect(r.wishes[2].sentence == "Iemand wil graag: pannenkoeken")
        // Boodschappen eerst bij de ouders.
        #expect(FamilyWish.groceriesFirst(r.wishes).map(\.id) == [4, 3, 5])
    }

    @Test func wishToListWithLinkWhenAHNotConnected() throws {
        let linked = try API.decoder.decode(WishToListResponse.self, from: Data(
            #"{"ok": true, "product": "AH Stroopwafels", "url": "https://www.ah.nl/mijnlijst/add-multiple?p=1"}"#.utf8))
        #expect(linked.url != nil)
        #expect(linked.product == "AH Stroopwafels")
        let onList = try API.decoder.decode(WishToListResponse.self, from: Data(
            #"{"ok": true, "product": "AH Stroopwafels", "wishes": []}"#.utf8))
        #expect(onList.url == nil)
        #expect(onList.wishes?.isEmpty == true)
    }

    @Test func wishBodyEncoding() throws {
        let recipe = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WishBody(recipeId: 7))) as? [String: Any]
        #expect(recipe?["recipe_id"] as? Int == 7)
        #expect(recipe?["kind"] as? String == "eten")
        let grocery = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(WishBody(text: "koekjes", kind: .boodschap))) as? [String: Any]
        #expect(grocery?["recipe_id"] == nil)
        #expect(grocery?["text"] as? String == "koekjes")
        #expect(grocery?["kind"] as? String == "boodschap")
    }

    @Test func memberDraftsForSaving() throws {
        let drafts = [MemberDraft(serverID: "nelleke", name: " Nelleke ", role: .ouder), MemberDraft(name: "Bo", role: .kind)]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MembersSaveBody(members: drafts))) as? [String: Any]
        let list = json?["members"] as? [[String: Any]]
        #expect(list?[0]["id"] as? String == "nelleke")
        #expect(list?[0]["name"] as? String == "Nelleke")
        #expect(list?[1]["id"] == nil)
        #expect(list?[1]["role"] as? String == "kind")
        #expect(MemberDraft.canSave(drafts))
        #expect(!MemberDraft.canSave([MemberDraft(name: "Bo", role: .kind)]))
        #expect(!MemberDraft.canSave([MemberDraft(name: "  ", role: .ouder)]))
    }

    // MARK: Kinderrol

    private func freshDefaults() -> UserDefaults {
        let name = "FamilyTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func nobodyChosenAsksWhoYouAre() {
        let family = FamilyModel(memberID: "", defaults: freshDefaults())
        #expect(family.needsPick)
        #expect(!family.isKid)
        #expect(family.isParent)
        family.skip()
        #expect(!family.needsPick)
    }

    @Test func kidRoleComesFromChosenMember() throws {
        let family = FamilyModel(memberID: "hannah", defaults: freshDefaults())
        try family.apply(decoded())
        #expect(family.current?.name == "Hannah")
        #expect(family.isKid)
        #expect(!family.isParent)
        #expect(!family.needsPick)
        #expect(family.ahConnected == false)
    }

    @Test func parentIsNotKid() throws {
        let family = FamilyModel(memberID: "nelleke", defaults: freshDefaults())
        try family.apply(decoded())
        #expect(!family.isKid)
    }

    @Test func removedMemberMustChooseAgain() throws {
        let family = FamilyModel(memberID: "oma", defaults: freshDefaults())
        try family.apply(decoded())
        #expect(family.needsPick)
    }

    @Test func myHeartFollowsMyInitial() throws {
        let family = FamilyModel(memberID: "hannah", defaults: freshDefaults())
        #expect(family.isMine(fans: ["H"], fallback: false) == false) // nog niet geladen: gezinsfavoriet
        try family.apply(decoded())
        #expect(family.isMine(fans: ["H", "S"], fallback: false))
        #expect(!family.isMine(fans: ["N"], fallback: true))
        #expect(family.isMine(fans: nil, fallback: true)) // oudere server zonder fans
    }

    @Test func kidFavoritesAreHerOwn() {
        let mine = RecipeSummary(id: 1, name: "Pannenkoeken", servings: "", totalTime: "", imageUrl: "",
                                 gfMode: .none, favorite: true, fans: ["H"])
        let papa = RecipeSummary(id: 2, name: "Chili", servings: "", totalTime: "", imageUrl: "",
                                 gfMode: .none, favorite: true, fans: ["G"])
        let archived = RecipeSummary(id: 3, name: "Oud", servings: "", totalTime: "", imageUrl: "",
                                     gfMode: .none, favorite: true, archived: true, fans: ["H"])
        #expect(KidWishesModel.mine([mine, papa, archived], initial: "H").map(\.id) == [1])
    }

    @Test func kidRoleIsRememberedBeforeLoading() throws {
        let defaults = freshDefaults()
        let first = FamilyModel(memberID: "hannah", defaults: defaults)
        try first.apply(decoded())
        // Volgende start: nog niet geladen, toch geen ouder-knoppen voor Hannah.
        let next = FamilyModel(memberID: "hannah", defaults: defaults)
        #expect(next.current == nil)
        #expect(next.isKid)
    }

    @Test func familyFavoritesForKidWithoutOwn() {
        func r(_ id: Int, _ fans: [String], archived: Bool = false) -> RecipeSummary {
            RecipeSummary(id: id, name: "R\(id)", servings: "", totalTime: "", imageUrl: "", gfMode: .none,
                          favorite: true, archived: archived, fans: fans)
        }
        let list = [r(1, ["G"]), r(2, ["G", "N", "S"]), r(3, ["H"]), r(4, ["N"], archived: true), r(5, [])]
        #expect(KidWishesModel.others(list, initial: "H").map(\.id) == [2, 1])
        #expect(KidWishesModel.others(list, initial: nil).isEmpty)
    }
}
