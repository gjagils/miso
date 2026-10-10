import Foundation

/// Naar het weekmenu (boodschappen en vriezer) vanuit Plannen of Vandaag. `week` nil = deze week.
struct WeekmenuRoute: Hashable {
    var week: String?
}
