import Foundation

/// Nieuw aantal personen voor een planregel: een getal, of terug naar de huishoudgrootte (`null`).
enum PersonsChange: Equatable {
    case count(Int)
    case household

    /// Bij het huishouden-aantal stuurt de app `null`, zodat de regel de instelling blijft volgen (zoals de web-versie).
    static func from(_ persons: Int, household: Int) -> PersonsChange {
        persons == household ? .household : .count(persons)
    }
}
