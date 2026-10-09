import Foundation

/// Eén dag in de rij dagchips van het Inplannen-scherm.
struct DayChip: Identifiable, Equatable {
    let date: String
    /// "ma", "di", …
    let weekdayShort: String
    let dayNumber: Int
    /// Titels van wat er die dag al staat (leeg = vrij).
    let occupied: [String]
    let isPast: Bool
    let isToday: Bool

    var id: String { date }
    var isOccupied: Bool { !occupied.isEmpty }

    /// "Maandag 12 okt, al gepland: Lasagne"
    var accessibilityLabel: String {
        let label = KiezenDates.label(date)
        return isOccupied ? "\(label), al gepland: \(occupied.joined(separator: ", "))" : label
    }
}
