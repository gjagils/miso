import Foundation

/// Wanneer telt koken als "gekookt"? Pas als minstens de helft van de stappen is afgevinkt.
enum CookProgress {
    static func isHalfway(done: Int, steps: Int) -> Bool {
        guard steps > 0 else { return false }
        return done >= (steps + 1) / 2
    }
}
