import Foundation
import Testing
@testable import AHRecepten

struct WeekTemplateTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func listDecodesAndSummarises() throws {
        let r = try decode(TemplateListResponse.self, #"""
        {"ok": true, "templates": [
          {"id": 2, "name": "Standaardweek", "created_on": "2026-10-12", "count": 3,
           "days": [{"weekday": 4, "label": "Pizza halen", "missing": false},
                    {"weekday": 0, "label": "Lasagne", "missing": false},
                    {"weekday": 2, "label": "(recept verwijderd)", "missing": true}]}]}
        """#)
        let t = try #require(r.templates.first)
        #expect(t.id == 2 && t.count == 3 && t.createdOn == "2026-10-12")
        // gesorteerd op weekdag, ongeacht de volgorde van de server
        #expect(t.summary == "ma Lasagne · wo (recept verwijderd) · vr Pizza halen")
        #expect(t.days.contains { $0.missing })
        let empty = try decode(TemplateListResponse.self, #"{"ok": true}"#)
        #expect(empty.templates.isEmpty)
    }

    @Test func applySummary() throws {
        let r = try decode(TemplateApplyResponse.self, #"""
        {"ok": true, "placed": 3, "skipped_busy": 1, "skipped_gone": 2, "week": "2026-10-19"}
        """#)
        #expect(r.summary == "3 dagen gevuld, 1 bezette dag overgeslagen, 2 verwijderde recepten overgeslagen.")
        #expect(TemplateApplyResponse(placed: 1).summary == "1 dag gevuld.")
        let failed = try decode(TemplateApplyResponse.self, #"{"ok": false, "error": "Dit sjabloon bestaat niet (meer)."}"#)
        #expect(!failed.ok && failed.error == "Dit sjabloon bestaat niet (meer)." && failed.placed == 0)
    }

    @Test func saveResponseCarriesError() throws {
        let bad = try decode(TemplateSaveResponse.self, #"{"ok": false, "error": "Deze week is nog leeg, dus er valt niets te bewaren."}"#)
        #expect(!bad.ok && bad.error?.contains("leeg") == true && bad.template == nil)
        let good = try decode(TemplateSaveResponse.self, #"{"ok": true, "template": {"id": 1, "name": "A", "count": 1, "days": []}}"#)
        #expect(good.ok && good.template?.name == "A")
    }

    @Test func bodies() throws {
        let save = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TemplateSaveBody(name: "A", week: "2026-10-12"))) as? [String: Any]
        #expect(save?["name"] as? String == "A" && save?["week"] as? String == "2026-10-12")
        let apply = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TemplateApplyBody(week: "2026-10-19", replace: true))) as? [String: Any]
        #expect(apply?["replace"] as? Bool == true)
    }
}
