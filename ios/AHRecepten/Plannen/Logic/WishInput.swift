import Foundation

/// Wens voor één dag: een knop óf een gerecht als tekst (net als op /plannen sluiten die elkaar uit).
struct WishInput: Hashable, Sendable {
    var chip: WishChip?
    var text = ""

    /// Wat naar de server gaat: chip-sleutel of het getypte gerecht; nil = geen wens.
    var value: String? {
        if let chip { return chip.rawValue }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isEmpty: Bool { value == nil }

    /// Wens van de server (zin-invoer) of uit een vorige keer: chip als die bestaat, anders tekst.
    init(serverValue: String) {
        if let chip = WishChip(rawValue: serverValue.lowercased()) {
            self.chip = chip
        } else {
            text = serverValue
        }
    }

    init(chip: WishChip? = nil, text: String = "") {
        self.chip = chip
        self.text = text
    }

    /// Tik op een knop: aanzetten (tekst weg) of, als hij al aan stond, uitzetten.
    mutating func toggle(_ tapped: WishChip) {
        chip = chip == tapped ? nil : tapped
        text = ""
    }

    /// Typen wist de knop.
    mutating func setText(_ newText: String) {
        text = newText
        if !newText.isEmpty { chip = nil }
    }
}
