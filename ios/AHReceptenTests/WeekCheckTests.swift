import Foundation
import Testing
@testable import AHRecepten

/// Week-check onder het voorstel, geen dubbel gerecht via alternatieven, en "Wijzig" = replace.
struct WeekCheckTests {
    private func option(_ id: Int, _ name: String, eiwit: String = "", keuken: String = "") -> ProposalOption {
        ProposalOption(recipeId: id, name: name, eiwit: eiwit, keuken: keuken)
    }

    @Test func lineLikeWeb() {
        let picks = [option(1, "Curry", eiwit: "vega", keuken: "indiaas"),
                     option(2, "Zalm", eiwit: "vis", keuken: "nederlands"),
                     option(3, "Chili", eiwit: "vlees", keuken: "mexicaans"),
                     option(4, "Kip tikka", eiwit: "kip", keuken: "indiaas"),
                     option(5, "Dahl", eiwit: "vega")]
        #expect(WeekCheck.line(picks: picks, freezerDays: 0)
                == "2× vega · 1× vis · 2× vlees/kip · 3 keukens · geen dubbelingen ✅")
        #expect(WeekCheck.line(picks: [option(1, "Curry"), option(2, "curry")], freezerDays: 1)
                == "0× vega · 0× vis · 0× vlees/kip · 1× vriezer · ⚠️ 1 dubbel")
        #expect(WeekCheck.line(picks: [option(1, "Pasta", keuken: "italiaans")], freezerDays: 0)
                == "0× vega · 0× vis · 0× vlees/kip · 1 keuken · geen dubbelingen ✅")
    }

    private func selection(replacing: Set<String> = []) -> ProposalSelection {
        let mon = ProposalDay(date: "2026-10-12", kind: .recipe,
                              options: [option(1, "Nasi", eiwit: "kip"), option(2, "Lasagne", eiwit: "vlees"), option(3, "Wraps")])
        let tue = ProposalDay(date: "2026-10-13", kind: .recipe,
                              options: [option(2, "Lasagne", eiwit: "vlees"), option(1, "Nasi"), option(4, "Dahl", eiwit: "vega")])
        return ProposalSelection(days: [mon, tue], replacing: replacing)
    }

    @Test func alternativesHideWhatIsPickedElsewhere() {
        var s = selection()
        let mon = s.days[0], tue = s.days[1]
        // Ma = Nasi, di = Lasagne: ma biedt geen Lasagne meer aan, di geen Nasi.
        #expect(s.alternatives(for: mon).map(\.option.name) == ["Wraps"])
        #expect(s.alternatives(for: tue).map(\.option.name) == ["Dahl"])
        s.choose(2, for: tue) // di → Dahl: Lasagne komt weer vrij voor maandag
        #expect(s.alternatives(for: mon).map(\.option.name) == ["Lasagne", "Wraps"])
        #expect(s.weekCheck == "1× vega · 0× vis · 1× vlees/kip · geen dubbelingen ✅")
    }

    @Test func replaceOnlyForChangedDays() {
        let s = selection(replacing: ["2026-10-13"])
        #expect(s.choices.map(\.replace) == [false, true])
        let body = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(s.choices[1])) as? [String: Any]
        #expect(body?["replace"] as? Bool == true)
    }

    @Test func proposeBodySendsReplace() throws {
        let body = ProposeBody(week: "2026-10-12", wishes: ["2026-10-13": "snel"], replace: ["2026-10-13"])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        #expect(json?["replace"] as? [String] == ["2026-10-13"])
    }

    @Test func changedDayIsOpenAgain() {
        var day = PlannenDay(date: "2026-10-13", taken: "Lasagne", isPast: false, entryIDs: [9])
        #expect(!day.isOpen)
        #expect(day.canChange)
        day.replacing = true
        #expect(day.isOpen)
        let wishes = ["2026-10-13": WishInput(chip: .snel)]
        #expect(PlannenLogic.collect(wishes, days: [day]) == ["2026-10-13": "snel"])
    }

    @Test func decodesProfileFields() throws {
        let json = #"{"recipe_id": 1, "name": "Curry", "eiwit": "vega", "keuken": "indiaas", "basis": "rijst"}"#
        let o = try API.decoder.decode(ProposalOption.self, from: Data(json.utf8))
        #expect(o.eiwit == "vega")
        #expect(o.keuken == "indiaas")
        #expect(o.basis == "rijst")
        let old = try API.decoder.decode(ProposalOption.self, from: Data(#"{"recipe_id": 1, "name": "X"}"#.utf8))
        #expect(old.eiwit.isEmpty)
    }
}
