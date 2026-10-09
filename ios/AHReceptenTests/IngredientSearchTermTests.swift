import Testing
@testable import AHRecepten

struct IngredientSearchTermTests {
    @Test(arguments: [
        ("2 gele paprika's", "gele paprika's"),
        ("200 g geraspte kaas", "geraspte kaas"),
        ("200g bloem", "bloem"),
        ("1 ui, gesnipperd", "ui"),
        ("2 teentjes knoflook (geperst)", "knoflook"),
        ("1/2 tl kurkuma", "kurkuma"),
        ("½ bos koriander", "koriander"),
        ("1 blik tomatenblokjes", "tomatenblokjes"),
        ("2-3 el olijfolie", "olijfolie"),
        ("Zout en peper", "zout en peper"),
        ("4", "4"),
    ])
    func searchTerm(_ input: String, _ expected: String) {
        #expect(IngredientSearchTerm.from(input) == expected)
    }
}
