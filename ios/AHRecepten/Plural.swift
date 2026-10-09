import Foundation

/// "1 product" / "3 producten". Nederlands kent geen automatische verbuiging in Foundation.
func plural(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
}
