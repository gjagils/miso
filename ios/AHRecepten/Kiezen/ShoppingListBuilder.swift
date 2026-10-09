import Foundation

/// Voegt de ingrediënten van de gekozen recepten samen tot één boodschappenlijst.
/// Zelfde logica als backend/app/templates/kiezen.html. Puur: geen netwerk, geen UI.
enum ShoppingListBuilder {
    struct Result {
        var products: [ShopProduct]
        /// Ingrediënten zonder gekoppeld AH-product.
        var unmatched: [ShopLine]
        /// Overgeslagen ingrediënten (basisvoorraad, "heb je al").
        var pantry: [ShopLine]
        /// Aantal producten voor het AH-lijstje (van de server als die het weet, anders de lijstlengte).
        var productCount: Int
    }

    /// Exacte aantallen per product-id uit de lijst-link van de server (`?p=<id>:<aantal>&p=...`).
    static func quantities(fromListLink url: URL?) -> [Int: Int] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var qty: [Int: Int] = [:]
        for item in items where item.name == "p" {
            let parts = (item.value ?? "").split(separator: ":")
            if parts.count == 2, let pid = Int(parts[0]), let q = Int(parts[1]) { qty[pid] = q }
        }
        return qty
    }

    /// - Parameters:
    ///   - recipes: geladen recepten, in de gekozen volgorde.
    ///   - quantities: aantallen uit de lijst-link; als die er zijn, tellen alleen die producten mee.
    ///   - linkCount: aantal producten volgens de server (0 = onbekend).
    static func build(recipes: [RecipeDetail], quantities: [Int: Int] = [:], linkCount: Int = 0) -> Result {
        var merged: [Int: ShopProduct] = [:]
        var order: [Int] = []
        var missing: [ShopLine] = []
        var have: [ShopLine] = []

        for rec in recipes {
            for ing in rec.ingredients {
                func add(_ pid: Int, _ name: String, _ size: String, _ img: String) {
                    if merged[pid] == nil {
                        merged[pid] = ShopProduct(id: pid, name: name, size: size, image: img, qty: 0, recipes: [])
                        order.append(pid)
                    }
                    merged[pid]?.qty += ing.packs
                    if merged[pid]?.recipes.contains(rec.name) == false { merged[pid]?.recipes.append(rec.name) }
                }
                if ing.skip {
                    have.append(ShopLine(text: ing.text, recipeId: rec.id, recipeName: rec.name))
                    continue
                }
                if let pid = ing.productId {
                    add(pid, ing.product ?? ing.text, ing.unitSize ?? "", ing.productImage ?? "")
                } else {
                    missing.append(ShopLine(text: ing.text, recipeId: rec.id, recipeName: rec.name))
                }
                if let gid = ing.gfProductId {
                    add(gid, (ing.gfProduct ?? "Product") + " (glutenvrij)", "", "")
                }
            }
        }

        var list = order.compactMap { merged[$0] }.filter { quantities.isEmpty || quantities[$0.id] != nil }
        for i in list.indices {
            if let q = quantities[list[i].id] { list[i].qty = q }
        }
        return Result(products: list, unmatched: missing, pantry: have,
                      productCount: linkCount > 0 ? linkCount : list.count)
    }
}
