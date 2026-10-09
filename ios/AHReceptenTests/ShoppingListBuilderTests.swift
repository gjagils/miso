import Foundation
import Testing
@testable import AHRecepten

struct ShoppingListBuilderTests {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Recept zoals de server het stuurt (snake_case JSON).
    private func recipe(id: Int, name: String, ingredients: [[String: Any]]) throws -> RecipeDetail {
        let full: [[String: Any]] = ingredients.map { ing in
            var i: [String: Any] = ["skip": false, "gluten": false, "gf_search": ""]
            i.merge(ing) { _, new in new }
            return i
        }
        let json: [String: Any] = [
            "id": id, "name": name, "servings": "4", "total_time": "", "image_url": "",
            "gf_mode": "none", "gf_note": "", "description": "", "source_url": "",
            "instructions": [], "ingredients": full,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try Self.decoder.decode(RecipeDetail.self, from: data)
    }

    @Test func mergesSameProductAcrossRecipes() throws {
        let a = try recipe(id: 1, name: "Pasta", ingredients: [
            ["text": "1 ui", "product_id": 10, "product": "AH Ui", "quantity": "1", "unit_size": "1 st"],
            ["text": "pasta", "product_id": 20, "product": "Penne", "quantity": 2],
        ])
        let b = try recipe(id: 2, name: "Curry", ingredients: [
            ["text": "2 uien", "product_id": 10, "product": "AH Ui", "quantity": "1.5"],
        ])

        let result = ShoppingListBuilder.build(recipes: [a, b])

        #expect(result.products.map(\.id) == [10, 20])
        let ui = try #require(result.products.first)
        #expect(ui.qty == 3) // 1 + ceil(1.5)
        #expect(ui.recipes == ["Pasta", "Curry"])
        #expect(ui.size == "1 st")
        #expect(result.products[1].qty == 2)
        #expect(result.productCount == 2)
    }

    @Test func splitsUnmatchedAndPantry() throws {
        let r = try recipe(id: 5, name: "Soep", ingredients: [
            ["text": "zout", "skip": true],
            ["text": "rare kruiden"],
            ["text": "bouillon", "product_id": "30", "product": "Bouillon"], // id als string: ook goed
        ])

        let result = ShoppingListBuilder.build(recipes: [r])

        #expect(result.pantry.map(\.text) == ["zout"])
        #expect(result.unmatched.map(\.text) == ["rare kruiden"])
        #expect(result.unmatched.first?.recipeId == 5)
        #expect(result.products.map(\.id) == [30])
        #expect(result.products.first?.qty == 1) // geen hoeveelheid: minimaal 1 verpakking
    }

    @Test func addsGlutenFreeProduct() throws {
        let r = try recipe(id: 1, name: "Lasagne", ingredients: [
            ["text": "lasagnebladen", "gluten": true, "product_id": 40, "product": "Lasagne",
             "gf_product_id": 41, "gf_product": "Glutenvrije lasagne"],
        ])

        let result = ShoppingListBuilder.build(recipes: [r])

        #expect(result.products.map(\.id) == [40, 41])
        #expect(result.products[1].name == "Glutenvrije lasagne (glutenvrij)")
    }

    @Test func serverQuantitiesWinAndFilter() throws {
        let r = try recipe(id: 1, name: "Pasta", ingredients: [
            ["text": "ui", "product_id": 10, "product": "Ui", "quantity": "1"],
            ["text": "olie", "product_id": 11, "product": "Olie", "quantity": "1"],
        ])
        let link = try #require(URL(string: "https://www.ah.nl/mijnlijst/add-multiple?p=10:4&p=99:1&x=1"))
        let qty = ShoppingListBuilder.quantities(fromListLink: link)
        #expect(qty == [10: 4, 99: 1])

        let result = ShoppingListBuilder.build(recipes: [r], quantities: qty, linkCount: 2)

        #expect(result.products.map(\.id) == [10]) // olie staat niet in de link (bijv. al op het lijstje)
        #expect(result.products.first?.qty == 4)
        #expect(result.productCount == 2)
    }

    @Test func quantitiesFromMissingOrMalformedLink() {
        #expect(ShoppingListBuilder.quantities(fromListLink: nil).isEmpty)
        let url = URL(string: "https://example.com/?p=abc&p=1:2:3&p=7:x")
        #expect(ShoppingListBuilder.quantities(fromListLink: url).isEmpty)
    }

    @Test func emptyInput() {
        let result = ShoppingListBuilder.build(recipes: [])
        #expect(result.products.isEmpty)
        #expect(result.productCount == 0)
    }
}
