import Foundation

/// `{"week": "YYYY-MM-DD"}` voor `POST /api/plan/sync` en `POST /api/week/suggest`.
struct WeekBody: Encodable {
    let week: String
}
