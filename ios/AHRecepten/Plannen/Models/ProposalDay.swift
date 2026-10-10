import Foundation

/// Voorstel voor één dag uit `POST /api/plan/propose`.
struct ProposalDay: Decodable, Identifiable, Hashable, Sendable {
    var id: String { date }
    let date: String
    /// Wat je typte of koos ("rijst", "lasagne").
    let wish: String
    /// Begrepen wens (chip, of het gerecht als tekst).
    let chip: String
    /// "Rijst", "Geen idee", of het gerecht.
    let label: String
    let kind: ProposalKind
    /// Bij `taken`: wat er al staat.
    let taken: String?
    /// Beste keuze eerst, daarna tot twee alternatieven.
    let options: [ProposalOption]

    enum CodingKeys: String, CodingKey { case date, wish, chip, label, kind, taken, options }

    init(date: String, wish: String = "", chip: String = "", label: String = "", kind: ProposalKind,
         taken: String? = nil, options: [ProposalOption] = []) {
        self.date = date
        self.wish = wish
        self.chip = chip
        self.label = label
        self.kind = kind
        self.taken = taken
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        wish = c.lenient(String.self, .wish) ?? ""
        chip = c.lenient(String.self, .chip) ?? wish
        label = c.lenient(String.self, .label) ?? wish
        options = c.lenient([ProposalOption].self, .options) ?? []
        let decodedKind = c.lenient(ProposalKind.self, .kind) ?? (options.isEmpty ? .none : .recipe)
        // Een recept-dag zonder opties kan de app niets mee; toon hem als "niets gevonden".
        kind = decodedKind == .recipe && options.isEmpty ? .none : decodedKind
        taken = c.lenient(String.self, .taken)
    }
}
