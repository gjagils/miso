import Foundation

/// Product uit `GET /api/ah/search`. Gaat ongewijzigd (met snake_case-sleutels) terug naar de server
/// bij koppelen, zodat de server dezelfde gegevens opslaat als bij de web-versie.
struct AHProduct: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    var unitSize = ""
    var price = ""
    var imageUrl = ""
    var brand = ""
    var category = ""
    var available = true
    var organic = false
    var unitPrice = ""
    var nix18 = false

    /// Bij decoderen zet `API.decoder` snake_case om naar camelCase.
    private enum CodingKeys: String, CodingKey {
        case id, name, unitSize, price, imageUrl, brand, category, available, organic, unitPrice, nix18
    }

    /// Bij versturen dezelfde sleutels als de server ze geeft.
    private enum EncodingKeys: String, CodingKey {
        case id, name, price, brand, category, available, organic, nix18
        case unitSize = "unit_size", imageUrl = "image_url", unitPrice = "unit_price"
    }

    init(id: Int, name: String, unitSize: String = "", price: String = "", imageUrl: String = "") {
        self.id = id
        self.name = name
        self.unitSize = unitSize
        self.price = price
        self.imageUrl = imageUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Product zonder id")
        }
        self.id = id
        name = c.lenient(String.self, .name) ?? ""
        unitSize = c.lenient(String.self, .unitSize) ?? ""
        // Prijs is meestal tekst ("2.49"), maar kan als getal binnenkomen.
        price = c.lenient(String.self, .price) ?? c.lenient(Double.self, .price).map { String(format: "%.2f", $0) } ?? ""
        imageUrl = c.lenient(String.self, .imageUrl) ?? ""
        brand = c.lenient(String.self, .brand) ?? ""
        category = c.lenient(String.self, .category) ?? ""
        available = c.lenient(Bool.self, .available) ?? true
        organic = c.lenient(Bool.self, .organic) ?? false
        unitPrice = c.lenient(String.self, .unitPrice) ?? ""
        nix18 = c.lenient(Bool.self, .nix18) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: EncodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(unitSize, forKey: .unitSize)
        try c.encode(price, forKey: .price)
        try c.encode(imageUrl, forKey: .imageUrl)
        try c.encode(brand, forKey: .brand)
        try c.encode(category, forKey: .category)
        try c.encode(available, forKey: .available)
        try c.encode(organic, forKey: .organic)
        try c.encode(unitPrice, forKey: .unitPrice)
        try c.encode(nix18, forKey: .nix18)
    }

    /// "€ 2,49" in Nederlandse notatie; leeg als er geen prijs is.
    var priceText: String {
        guard let value = Double(price) else { return "" }
        return value.formatted(.currency(code: "EUR").locale(Locale(identifier: "nl_NL")))
    }
}
