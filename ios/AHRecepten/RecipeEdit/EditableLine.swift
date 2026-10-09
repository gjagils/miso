import Foundation

/// Regel in het bewerkscherm (ingrediënt of bereidingsstap) met een vast id, zodat verplaatsen en
/// verwijderen in een lijst goed gaat terwijl je typt.
struct EditableLine: Identifiable, Hashable {
    let id: UUID
    var text: String

    init(_ text: String, id: UUID = UUID()) {
        self.id = id
        self.text = text
    }
}
