# Plannings-API (weekmenu) — contract voor web en iOS

Eén API voor alle clients. Code: `backend/app/api/plan.py`, domeinlogica `backend/app/planning.py`.
Authenticatie zoals de rest van de JSON-API: `Authorization: Bearer <token>` (uit `POST /api/login`), of de
sessie-cookie. Fouten: HTTP 4xx met `{"ok": false, "error": "<Nederlandse melding>"}`; pydantic-validatie
(bijv. `persons: 0`, onbekende `kind`) geeft 422 met FastAPI's `detail`. Datums zijn altijd `YYYY-MM-DD`.

## Begrippen

Een **planregel** (entry) = dag + soort + personen.

| kind | betekenis | boodschappen |
|---|---|---|
| `recipe` | recept koken | ingrediënten × (personen / porties van het recept); × 2 als `cook_double` gezet is |
| `leftover` | "Rest van …" (meestal automatisch door *kook dubbel, morgen opeten*) | geen |
| `stock` | "Uit de vriezer / hebben we al": vrije tekst + optionele extra's | elke extra 1× (gekoppeld aan een AH-product) |

- `persons: null` betekent: huishoudgrootte (instelling `household_size`, default 4). De response geeft altijd
  het effectieve aantal in `persons` en `persons_is_default`.
- Schalen: het aantal porties komt uit `recipe.servings` ("4 personen" → 4; onbekend → 4). Vergelijkbare
  hoeveelheden (g/ml/stuks met bekende verpakking) worden vermenigvuldigd en dan naar verpakkingen afgerond
  (minimaal 1). Andere hoeveelheden gaan pas omhoog vanaf factor 1,5 (`ceil(qty × factor)`), nooit omlaag.
- Meerdere regels per dag zijn toegestaan.

### Entry-object (in alle responses)

```json
{
  "entry_id": 12,
  "date": "2026-10-12",
  "kind": "recipe",
  "title": "Lasagne bolognese",          // recept-naam / "Rest van <recept>" / vrije tekst
  "persons": 6,                          // effectief aantal
  "persons_is_default": false,           // true = volgt household_size
  "grocery_persons": 12,                 // waarvoor ingekocht wordt (0 voor leftover/stock)
  "recipe_id": 1,                        // null bij stock
  "recipe": {"id": 1, "name": "Lasagne bolognese", "servings": "4 personen", "total_time": "45 min",
             "image_url": "https://…", "gf_mode": "none"},          // null bij stock
  "text": "",                            // vrije tekst (stock)
  "extras": [                            // alleen stock
    {"text": "spaghetti", "product": "AH Spaghetti", "product_id": 159760, "product_image": "https://…"},
    {"text": "iets onvindbaars", "product": null, "product_id": null, "product_image": ""}
  ],
  "cook_double": "tomorrow",             // null | "tomorrow" | "freezer" (alleen recipe)
  "source_entry_id": null,               // bij leftover: de kookdag
  "leftover_entry_ids": [13]             // bij recipe: bijbehorende rest-dagen
}
```

## Planregels

### `GET /api/plan/entries?start=YYYY-MM-DD&days=7` of `?week=YYYY-MM-DD|next`

Regels in een periode (default: vandaag, 7 dagen; `days` 1–62). Handig voor de dagchips (bezette dagen).

```json
{"ok": true, "start": "2026-10-12", "end": "2026-10-18", "household_size": 4, "entries": [ <entry>, … ]}
```

### `POST /api/plan/entries`

```json
{
  "date": "2026-10-12",
  "kind": "recipe",                 // "recipe" (default) | "leftover" | "stock"
  "recipe_id": 1,                   // verplicht bij recipe/leftover
  "persons": 6,                     // optioneel, 1–20; weglaten/null = huishoudgrootte
  "text": "Pastasaus uit de vriezer", // stock (verplicht, tenzij freezer_item_id)
  "extras": ["pasta", "parmezaan"], // stock: strings of [{"text": "pasta"}]; max 20
  "cook_double": "tomorrow",        // recipe: null | "tomorrow" | "freezer"
  "freezer_item_id": 3              // stock: haal 1 portie uit de vriezer
}
```

Gedrag:
- `cook_double: "tomorrow"` maakt een tweede regel `leftover` op `date + 1` (zelfde personen,
  `source_entry_id` = kookdag) en verdubbelt de boodschappen van de kookdag.
- `cook_double: "freezer"` verdubbelt de boodschappen en zet een vriezer-item erbij
  (`name` = recept, `portions` = personen).
- `stock` met `freezer_item_id`: tekst wordt (als leeg) "<naam> uit de vriezer"; portions − 1; bij 0 wordt het
  item verwijderd. Extra's worden direct aan AH-producten gekoppeld (zelfde matcher als recepten, geen
  basisvoorraad-filter). Lukt koppelen niet (AH weg), dan probeert `POST /api/plan/sync` het later opnieuw.

Response (status = `week_status` van de week van `date`, zie onder):

```json
{
  "ok": true,
  "entries": [ <kookdag>, <leftover> ],   // alles wat is aangemaakt
  "freezer_item": null,                    // of {id, name, portions, added_on, from_recipe_id}
  "status": {"needed": 4, "missing": [{"name": "AH Rundergehakt 500 g", "quantity": 3}], "missing_count": 1,
             "unmatched": [], "complete": false, "on_list": 3, "locked": false}
}
```

Fouten: 400 ongeldige datum / stock zonder tekst; 404 recept of vriezer-item niet gevonden; 422 validatie.

### `PATCH /api/plan/entries/{entry_id}`

Alle velden optioneel; alleen meegestuurde velden worden aangepast.

```json
{"date": "2026-10-14", "persons": 5, "text": "Pannenkoeken", "extras": ["stroop"]}
```

- `date`: verplaatsen. Een rest-dag die op "kookdag + 1" stond schuift mee.
- `persons`: getal, of `null` = terug naar huishoudgrootte. Rest-dagen krijgen hetzelfde aantal.
- `text`, `extras`: alleen voor `stock` (extras op een andere soort → 400). Bestaande koppelingen blijven.

```json
{"ok": true, "entry": <entry>, "entries": [<entry>, <meegeschoven leftovers>], "status": {…},
 "weeks": ["2026-10-12"]}   // weken die geraakt zijn (bij verplaatsen naar een andere week: beide)
```

### `DELETE /api/plan/entries/{entry_id}`

Verwijdert de regel. Een kookdag neemt zijn rest-dagen mee. Een rest-dag weghalen zet `cook_double` van de
kookdag terug op `null` (niet meer dubbel inkopen).

```json
{"ok": true, "deleted": [12, 13], "status": {…}}
```

## Week (bestaand, uitgebreid)

### `GET /api/week?week=YYYY-MM-DD|next`

Bestaande velden blijven gelijk. Nieuw: `household_size`, per dag `entries`, en `entry_id` in elk recept.

```json
{
  "week": "2026-10-12", "prev_week": "2026-10-05", "next_week": "2026-10-19", "household_size": 4,
  "days": [
    {
      "date": "2026-10-12", "label": "Maandag 12 okt", "today": false,
      "recipes": [{"id": 1, "name": "Lasagne bolognese", "servings": "4 personen", "total_time": "",
                   "image_url": "", "gf_mode": "none", "entry_id": 12}],
      "entries": [ <entry>, … ]
    }
  ],
  "status": {"needed": 6, "missing": […], "missing_count": 6, "unmatched": [], "complete": false,
             "on_list": 0, "locked": false}
}
```

Let op: `recipes` bevat alleen `kind == "recipe"` (zodat de oude app via `POST /api/plan` geen restjes of
voorraad omzet in recepten). Nieuwe clients gebruiken `entries`.

`status`: `needed` = aantal verschillende AH-producten voor de week, `missing` = wat nog niet op het AH-lijstje
staat (delta), `missing_count`, `on_list` = producten die er al volledig op staan, `unmatched` =
ingrediënten/extra's zonder AH-product.

### Oud: `POST /api/plan` `{week, days: {date: [recipe_id…]}}`

Blijft werken (oude iOS-app), maar werkt nu als verschil op `recipe`-regels: bestaande regels (met personen,
kook-dubbel) blijven staan, `leftover`/`stock` worden niet aangeraakt; een weggehaald recept neemt zijn
rest-dagen mee. Nieuwe clients: gebruik de entry-endpoints.

## Boodschappen

- `POST /api/plan/sync {"week": "YYYY-MM-DD"}` — zet de delta (`status.missing`) op het AH-lijstje, inclusief
  geschaalde hoeveelheden en extra's. Response `{"ok", "added", "status"}`. Web-knop: "Zet N nieuwe producten
  op je AH-lijstje" (N = `status.missing_count`; 0 → "Je lijstje is bij"). `locked` blijft bestaan maar de UI
  gebruikt het niet meer.
- `POST /api/list-link` en `POST /api/basket/fill` accepteren naast `{week}` of `{recipe_ids}` nu ook
  `persons: {"<recipe_id>": 6}` (voor losse recepten; leeg = huishoudgrootte, dubbel koken = 2× personen
  meesturen). Met `{week}` wordt alles uit de planregels gehaald.
- Nooit: bestellen of afrekenen.

## Volgende week / besteldag

### `GET /api/plan/next-week-status`

```json
{
  "ok": true,
  "order_day": 6, "order_day_name": "zondag",
  "days_until_order": 2,                 // 0 = vandaag
  "week": "2026-10-12",                  // maandag van volgende week
  "planned_days": 4, "total_days": 7,    // dagen met minstens één regel (ook rest/voorraad)
  "missing_dates": ["2026-10-16", "2026-10-17", "2026-10-18"],
  "prominent": true,                     // days_until_order <= 2: toon groot
  "message": "Volgende week: 4 van 7 dagen gepland · nog 2 dagen tot zondag (besteldag)",
  "list_status": {"needed": 6, "missing_count": 6, "missing": [{"name": "…", "quantity": 2}],
                  "unmatched_count": 0, "complete": false}
}
```

`message` varianten: "… · morgen is het zondag (besteldag)", "… · vandaag is het zondag (besteldag)".
Acties in de UI: "Plan volgende week" (web: `/kiezen?week=next`) en "Laat Miso voorstellen"
(`POST /api/week/suggest {"week": "<week>"}` → `voorstel: [{date, recipe_id, name, profiel}]`, daarna per
voorstel `POST /api/plan/entries`).

## Instellingen

- `GET /api/plan/settings` → `{"ok": true, "household_size": 4, "order_weekday": 6, "order_weekday_name": "zondag"}`
- `PATCH /api/plan/settings {"household_size": 5, "order_weekday": 0}` (beide optioneel; 1–20 en 0=ma … 6=zo)
  → zelfde vorm. Web: formulier "Gezin en besteldag" op `/settings`.

## Vriezer

Item: `{"id": 3, "name": "Pasta pesto", "portions": 3, "added_on": "2026-10-14", "from_recipe_id": 2}`

| | |
|---|---|
| `GET /api/freezer` | `{"ok": true, "items": [item…]}` (portions > 0, oudste eerst) — gebruik dit als suggesties bij een "uit de vriezer"-dag |
| `POST /api/freezer` | `{"name": "Soep", "portions": 2, "from_recipe_id": null, "added_on": null}` → `{"ok", "item"}` |
| `PATCH /api/freezer/{id}` | `{"name"?, "portions"?}`; `portions: 0` verwijdert → `{"ok", "item": null, "deleted": true}` |
| `DELETE /api/freezer/{id}` | `{"ok": true}`; 404 als het niet bestaat |

Een vriezer-item inplannen = `POST /api/plan/entries {"kind": "stock", "date", "freezer_item_id"}` (portie −1).

## Gezondheid

`GET /api/week/health` telt alleen gekookte recepten voor variatie (eiwit/basis/keuken); restjes tellen mee in
`dagen` (nieuw veld `restjes`), voorraad-dagen niet. `recepten[]` heeft nu ook `entry_id` (voor chips per dag).
`POST /api/week/suggest` stelt alleen dagen zonder enige regel voor.

## Database

Nieuwe kolommen op `plan_entries` (idempotent toegevoegd bij opstarten door `app/migrations.py`):
`kind` (default `'recipe'`), `persons`, `text`, `extras_json`, `source_entry_id`, `cook_double`.
`recipe_id` blijft NOT NULL; `0` = geen recept (stock). Nieuwe tabel `freezer_items`.
