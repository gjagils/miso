import Foundation

/// JSON-voorbeelden uit docs/plan-api.md (zonder commentaar), voor de decodeertests.
enum PlanFixtures {
    static let recipeEntry = #"""
    {
      "entry_id": 12, "date": "2026-10-12", "kind": "recipe", "title": "Lasagne bolognese",
      "persons": 6, "persons_is_default": false, "grocery_persons": 12, "recipe_id": 1,
      "recipe": {"id": 1, "name": "Lasagne bolognese", "servings": "4 personen", "total_time": "45 min",
                 "image_url": "https://example.com/l.jpg", "gf_mode": "none"},
      "text": "", "extras": [], "cook_double": "tomorrow", "source_entry_id": null, "leftover_entry_ids": [13]
    }
    """#

    static let leftoverEntry = #"""
    {
      "entry_id": 13, "date": "2026-10-13", "kind": "leftover", "title": "Rest van Lasagne bolognese",
      "persons": 6, "persons_is_default": false, "grocery_persons": 0, "recipe_id": 1,
      "recipe": {"id": 1, "name": "Lasagne bolognese", "servings": "4 personen", "total_time": "45 min",
                 "image_url": "", "gf_mode": "none"},
      "text": "", "extras": [], "cook_double": null, "source_entry_id": 12, "leftover_entry_ids": []
    }
    """#

    static let stockEntry = #"""
    {
      "entry_id": 14, "date": "2026-10-14", "kind": "stock", "title": "Pastasaus uit de vriezer",
      "persons": 4, "persons_is_default": true, "grocery_persons": 0, "recipe_id": null, "recipe": null,
      "text": "Pastasaus uit de vriezer",
      "extras": [
        {"text": "spaghetti", "product": "AH Spaghetti", "product_id": 159760, "product_image": "https://example.com/s.jpg"},
        {"text": "iets onvindbaars", "product": null, "product_id": null, "product_image": ""}
      ],
      "cook_double": null, "source_entry_id": null, "leftover_entry_ids": []
    }
    """#

    static let status = #"""
    {"needed": 4, "missing": [{"name": "AH Rundergehakt 500 g", "quantity": 3}], "missing_count": 1,
     "unmatched": [], "complete": false, "on_list": 3, "locked": false}
    """#

    static let entries = #"{"ok": true, "start": "2026-10-12", "end": "2026-10-18", "household_size": 4, "entries": ["#
        + recipeEntry + "," + leftoverEntry + "," + stockEntry + "]}"

    static let createResponse = #"{"ok": true, "entries": ["# + recipeEntry + "," + leftoverEntry
        + #"], "freezer_item": null, "status": "# + status + "}"

    static let patchResponse = #"{"ok": true, "entry": "# + recipeEntry + #", "entries": ["# + recipeEntry + ","
        + leftoverEntry + #"], "status": "# + status + #", "weeks": ["2026-10-12"]}"#

    static let deleteResponse = #"{"ok": true, "deleted": [12, 13], "status": "# + status + "}"

    static let week = #"""
    {
      "week": "2026-10-12", "prev_week": "2026-10-05", "next_week": "2026-10-19", "household_size": 4,
      "days": [
        {"date": "2026-10-12", "label": "Maandag 12 okt", "today": false,
         "recipes": [{"id": 1, "name": "Lasagne bolognese", "servings": "4 personen", "total_time": "",
                      "image_url": "", "gf_mode": "none", "entry_id": 12}],
         "entries": [
    """# + recipeEntry + #"""
        ]},
        {"date": "2026-10-14", "label": "Woensdag 14 okt", "today": false, "recipes": [], "entries": [
    """# + stockEntry + #"""
        ]}
      ],
      "status": {"needed": 6, "missing": [], "missing_count": 6, "unmatched": [], "complete": false,
                 "on_list": 0, "locked": false}
    }
    """#

    /// Oudere server: geen `entries`, `household_size`, `entry_id`, `missing_count` of `on_list`.
    static let legacyWeek = #"""
    {
      "week": "2026-10-12", "prev_week": "2026-10-05", "next_week": "2026-10-19",
      "days": [
        {"date": "2026-10-12", "label": "Maandag 12 okt", "today": false,
         "recipes": [{"id": 1, "name": "Lasagne", "servings": "", "total_time": "", "image_url": "", "gf_mode": "none"},
                     {"id": 1, "name": "Lasagne", "servings": "", "total_time": "", "image_url": "", "gf_mode": "none"}]}
      ],
      "status": {"needed": 2, "missing": [{"name": "Kaas", "quantity": 1}], "unmatched": [], "complete": false, "locked": false}
    }
    """#

    static let nextWeekStatus = #"""
    {
      "ok": true, "order_day": 6, "order_day_name": "zondag", "days_until_order": 2, "week": "2026-10-12",
      "planned_days": 4, "total_days": 7, "missing_dates": ["2026-10-16", "2026-10-17", "2026-10-18"],
      "prominent": true,
      "message": "Volgende week: 4 van 7 dagen gepland · nog 2 dagen tot zondag (besteldag)",
      "list_status": {"needed": 6, "missing_count": 6, "missing": [{"name": "Kaas", "quantity": 2}],
                      "unmatched_count": 0, "complete": false}
    }
    """#

    static let settings = #"{"ok": true, "household_size": 4, "order_weekday": 6, "order_weekday_name": "zondag"}"#

    static let freezerList = #"""
    {"ok": true, "items": [{"id": 3, "name": "Pasta pesto", "portions": 3, "added_on": "2026-10-14", "from_recipe_id": 2},
                           {"id": 4, "name": "Soep", "portions": "2", "added_on": null, "from_recipe_id": null}]}
    """#

    static let freezerDeleted = #"{"ok": true, "item": null, "deleted": true}"#

    static let health = #"""
    {"week": "2026-10-12", "dagen": 5, "restjes": 1, "gemiddeld_kcal": 620, "groente_g_per_dag": 180,
     "eiwit": {"vlees": 2}, "basis": {}, "keuken": {}, "schijf_pct": 80,
     "signalen": [{"type": "goed", "tekst": "Genoeg groente."}],
     "recepten": [{"date": "2026-10-12", "entry_id": 12, "recipe_id": 1, "name": "Lasagne",
                   "profiel": {"kcal": 700, "groente_g": 150, "eiwit": "vlees", "basis": "pasta", "keuken": "italiaans",
                               "volkoren": false, "schijf": {"groente_fruit": true}}},
                  {"date": "2026-10-13", "entry_id": 15, "recipe_id": 2, "name": "Zonder profiel", "profiel": null}]}
    """#

    static let suggest = #"""
    {"ok": true, "voorstel": [{"date": "2026-10-16", "recipe_id": 7, "name": "Visstoof",
                               "profiel": {"kcal": 500, "eiwit": "vis", "basis": "rijst", "keuken": "frans"}}],
     "zonder_profiel": 0, "analyse": {}}
    """#
}
