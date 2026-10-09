import Foundation
import Testing
@testable import AHRecepten

struct KoppelenTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try API.decoder.decode(type, from: Data(json.utf8))
    }

    private func encodeObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static let searchJSON = """
    {"products": [
      {"id": 4471, "name": "AH Biologisch Paprika geel", "unit_size": "2 stuks", "price": "2.49",
       "image_url": "https://static.ah.nl/x.jpg", "brand": "AH Biologisch", "category": "Groente",
       "available": true, "organic": true, "unit_price": "per stuk 1.25", "nix18": false},
      {"id": "5520", "name": "Paprika geel", "price": 1.1},
      {"name": "zonder id"}
    ]}
    """

    @Test func searchResponseSkipsUnreadableProducts() throws {
        let result = try decode(AHProductSearchResponse.self, Self.searchJSON)
        #expect(result.products.map(\.id) == [4471, 5520])
        let first = result.products[0]
        #expect(first.unitSize == "2 stuks")
        #expect(first.imageUrl == "https://static.ah.nl/x.jpg")
        #expect(first.organic)
        #expect(first.unitPrice == "per stuk 1.25")
        #expect(result.products[1].price == "1.10")
        #expect(result.products[1].available)
    }

    @Test func productEncodesWithServerKeys() throws {
        let product = try decode(AHProductSearchResponse.self, Self.searchJSON).products[0]
        let object = try encodeObject(product)
        #expect(object["id"] as? Int == 4471)
        #expect(object["unit_size"] as? String == "2 stuks")
        #expect(object["image_url"] as? String == "https://static.ah.nl/x.jpg")
        #expect(object["unit_price"] as? String == "per stuk 1.25")
        #expect(object["unitSize"] == nil)
        // En weer terug lezen geeft hetzelfde product.
        let again = try decode(AHProduct.self, String(decoding: try JSONEncoder().encode(product), as: UTF8.self))
        #expect(again == product)
    }

    @Test func priceText() {
        #expect(AHProduct(id: 1, name: "x", price: "2.49").priceText.contains("2,49"))
        #expect(AHProduct(id: 1, name: "x").priceText.isEmpty)
    }

    @Test func ingredientUpdateBodies() throws {
        let product = AHProduct(id: 7, name: "Ui", unitSize: "1 kg")
        let choose = try encodeObject(IngredientUpdateBody.choose(product, text: "2 uien"))
        #expect(choose["text"] as? String == "2 uien")
        #expect((choose["product"] as? [String: Any])?["unit_size"] as? String == "1 kg")
        #expect(choose["skip"] == nil && choose["quantity"] == nil)

        // Geen "product"-sleutel bij uitvinken of aantal: `"product": null` zou ontkoppelen.
        let skip = try encodeObject(IngredientUpdateBody.skip(true, text: "zout"))
        #expect(skip["skip"] as? Bool == true)
        #expect(skip.keys.contains("product") == false)
        let unskip = try encodeObject(IngredientUpdateBody.skip(false, text: "zout"))
        #expect(unskip["skip"] as? Bool == false)
        let quantity = try encodeObject(IngredientUpdateBody.quantity(3, text: "2 uien"))
        #expect(quantity["quantity"] as? Int == 3)
        #expect(quantity.keys.sorted() == ["quantity", "text"])
    }

    @Test func ingredientUpdateResponse() throws {
        let json = """
        {"ok": true, "ingredient": {"index": 2, "text": "2 gele paprika's", "skip": false, "gluten": false,
         "gf_search": "", "product": "AH Paprika geel", "product_id": 4471, "product_image": "",
         "quantity": 1, "pantry": false, "unit_size": "2 stuks", "manual": true,
         "gf_product": null, "gf_product_id": null}}
        """
        let result = try decode(IngredientUpdateResponse.self, json)
        let ingredient = try #require(result.ingredient)
        #expect(result.ok)
        #expect(ingredient.index == 2)
        #expect(ingredient.manual == true)
        #expect(ingredient.isMatched)
        #expect(ingredient.productId == 4471)
        #expect(ingredient.packs == 1)
    }

    @Test func ingredientFromOlderServerHasNoIndex() throws {
        let json = """
        {"text": "zout", "skip": true, "gluten": false, "gf_search": "", "product": null}
        """
        let ingredient = try decode(Ingredient.self, json)
        #expect(ingredient.index == nil)
        #expect(ingredient.manual == nil)
        #expect(!ingredient.isMatched)
        #expect(IngredientSelection(position: 4, ingredient: ingredient).serverIndex == 4)
    }

    static let missingJSON = """
    {"groups": [
      {"term": "gele paprika", "lines": [
        {"recipe_id": 1, "recipe": "Soep", "index": 0, "text": "2 gele paprika's"},
        {"recipe_id": 3, "recipe": "Wraps", "index": 4, "text": "1 gele paprika"},
        {"recipe_id": 1, "recipe": "Soep", "index": 6, "text": "gele paprika"}]},
      {"term": "kurkuma", "lines": [{"recipe_id": 2, "recipe": "Curry", "index": 1, "text": "1 tl kurkuma"}]}
    ], "totaal": {"pct": 94.3, "volledig": 88, "recepten": 141, "open": 12, "totaal": 900}}
    """

    @Test func missingResponse() throws {
        let result = try decode(MissingResponse.self, Self.missingJSON)
        #expect(result.groups.map(\.term) == ["gele paprika", "kurkuma"])
        #expect(result.groups[0].lines[1] == MissingLine(recipeId: 3, recipe: "Wraps", index: 4, text: "1 gele paprika"))
        #expect(result.groups[0].recipeNames == ["Soep", "Wraps"])
        #expect(result.totaal == CoverageTotals(pct: 94.3, volledig: 88, recepten: 141, open: 12))
        #expect(result.totaal.pctText.contains("94,3"))
        #expect(result.totaal.completeText == "88 van 141 recepten compleet")
        #expect(abs(result.totaal.fraction - 0.943) < 0.0001)
    }

    @Test func assignBodyEncodesLinesAndExplicitNull() throws {
        let line = MissingLine(recipeId: 1, recipe: "Soep", index: 0, text: "2 gele paprika's")
        let skip = try encodeObject(MissingAssignBody(lines: [line], product: nil))
        #expect(skip["product"] is NSNull)
        let lines = try #require(skip["lines"] as? [[String: Any]])
        #expect(lines[0]["recipe_id"] as? Int == 1)
        #expect(lines[0]["index"] as? Int == 0)
        #expect(lines[0]["text"] as? String == "2 gele paprika's")

        let choose = try encodeObject(MissingAssignBody(lines: [line], product: AHProduct(id: 9, name: "Paprika")))
        #expect((choose["product"] as? [String: Any])?["id"] as? Int == 9)
    }

    @MainActor
    @Test func applyingAnAssignmentRemovesTheGroupAndUpdatesTotals() throws {
        let response = try decode(MissingResponse.self, Self.missingJSON)
        let model = MissingModel(groups: response.groups, totals: response.totaal)
        #expect(model.lineCount == 4)
        let assign = try decode(MissingAssignResponse.self, """
        {"ok": true, "updated": 3, "totaal": {"pct": 95.1, "volledig": 90, "recepten": 141}}
        """)
        model.apply(assign, for: response.groups[0])
        #expect(model.totals?.volledig == 90)
        #expect(model.groups.map(\.term) == ["kurkuma"])
        #expect(model.lineCount == 1)
    }

    @Test func conflictError() {
        #expect(APIError(message: "x", status: 409).isConflict)
        #expect(!APIError(message: "x", status: 500).isConflict)
        #expect(!APIError(message: "x").isConflict)
    }
}
