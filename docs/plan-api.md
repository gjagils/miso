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

## Koken met wat er is (F11)

`GET /api/cook-with` → `{ok, suggestions, inventory}`. Leest alleen lokale gegevens: de vriezerlijst en de
boodschappenrondes van de laatste 4 dagen uit `ah_trips` (basisvoorraad uitgezonderd). Een eigen recept (niet gearchiveerd,
niet al gepland in de komende 7 dagen, niet net uit de vriezer gehaald) wordt voorgesteld als minstens 2 ingrediënten gedekt
zijn. Sortering: meeste gedekt, dan minste ontbrekend. Maximaal 6.

- `suggestions[]`: `{recipe_id, name, image_url, total_time, servings, covered, total, missing_count,
  matches: [{ingredient, from, source: "vriezer"|"gekocht"}]}`.
- `inventory`: `{freezer: [naam], bought: [{name, date}]}` (waar de voorstellen op gebaseerd zijn).
- Code: `backend/app/cookwith.py`. Restjes zijn al planregels en doen hier niet mee.

## Weeksjablonen (F9)

Een week bewaren en op een andere week terugzetten. Bewaard worden recept- en voorraadregels met weekdag,
personen en "morgen opeten" (`rest`); vriezer-effecten niet. Kinderen kunnen alleen lezen
(`POST /api/plan/templates` en `DELETE /api/plan/templates/…` staan in `KID_BLOCKED`). Tabel `week_templates`.

- `GET /api/plan/templates` → `{ok, templates: [{id, name, created_on, count, days: [{weekday 0-6, label, missing}]}]}`.
  `missing` = het recept bestaat niet meer.
- `POST /api/plan/templates` `{name, week?}` bewaart de week (ISO-datum erin, leeg = deze week). Zelfde naam
  overschrijft. Lege week: `{ok:false, error}`. Maximaal 30 sjablonen.
- `POST /api/plan/templates/{id}/apply` `{week?, replace?}` (`week`: ISO-datum of `"next"`) →
  `{ok, placed, skipped_busy, skipped_gone, week, entries, status}`. Bezette dagen (recept of voorraad) blijven staan
  tenzij `replace`. Een restje dat buiten de week zou vallen wordt weggelaten.
- `DELETE /api/plan/templates/{id}` → `{ok}`; onbekend id geeft 404.

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
                  "unmatched_count": 0, "complete": false},
  "bonus_hint": {"count": 2, "saving": 3.0, "names": ["Garnalen met rijst", "Kip met rijst"],
                 "message": "2 recepten van jullie zitten volgende week in de bonus (samen ongeveer €3,00 voordeel): …"}
}
```

`bonus_hint` (A5): eigen recepten waarvan een ingrediënt volgende week in de bonus zit (minstens €0,50 voordeel, uit
`ah_bonus_periods`; `message` is leeg als er geen bonus bekend is). De website toont de zin onder de banner "Volgende week";
de iOS-app plant er een lokale melding van op vrijdag 17:00 (alleen als die vrijdag nog vóór de maandag van `week` valt).
Code: `backend/app/bonushint.py`.

`message` varianten: "… · morgen is het zondag (besteldag)", "… · vandaag is het zondag (besteldag)".
Acties in de UI: "Plan volgende week" (web: `/kiezen?week=next`) en "Laat Miso voorstellen"
(`POST /api/week/suggest {"week": "<week>"}` → `voorstel: [{date, recipe_id, name, profiel}]`, daarna per
voorstel `POST /api/plan/entries`).

## Instellingen

- `GET /api/plan/settings` → `{"ok": true, "household_size": 4, "order_weekday": 6, "order_weekday_name": "zondag", "week_budget": 0, "kids_weekday": null}`
- `PATCH /api/plan/settings {"household_size": 5, "order_weekday": 0, "week_budget": 120, "kids_weekday": 2}` (alles optioneel; 1–20, 0=ma … 6=zo, 0–9999 euro per week met 0 = geen budget, en `kids_weekday` 0=ma … 6=zo of -1 voor geen; GET geeft `null` bij geen)

### Kids-kookavond (D8)

Eén vaste weekdag (`kids_weekday`) waarop de kinderen meekoken. Recepten met de vlag `kid_friendly` ("makkelijk met kinderen")
krijgen op die dag voorrang: in `POST /api/week/suggest` (reden "makkelijk met kinderen") en in `POST /api/plan/propose`
(optievelden `kid_friendly` en `kids_night`; `kids_night` is waar als het recept de vlag heeft en de dag de kids-avond is).
De vlag staat in elke receptsamenvatting (`kid_friendly`) en wordt gezet met `PATCH /api/recipes/{id}/flags {"kid_friendly": true}`
(alleen ouders; kinderen krijgen 403). Kolom `recipes.kid_friendly` (migratie). Code: `backend/app/kidsnight.py`.
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

## Voorstel: uitlegbare score

`POST /api/week/suggest` geeft per suggestie ook `score`, `redenen` (lijst) en `uitleg` (één regel), bijv.
"favoriet van Hannah, in de bonus (−€2,80), 4 weken niet gegeten, ongeveer €3,20 p.p.". Termen en gewichten
staan in `nutrition.WEIGHTS`: gezondheid en variatie, de voorkeursscore uit `app/usage.py` (favorieten, 👍/👎, vaak
gekozen, recent gegeten), bonus van de week waarvoor gepland wordt, lang niet gekookt / nog nooit, kosten per
persoon, open wensen (`wishes` met een recept). De context wordt gebouwd in `api/health.suggest_context`.

## AH-datalaag en inzichten

Lokale kopie van AH-gegevens (`backend/app/ah_sync.py`, tabellen `ah_trips`, `ah_prices`, `ah_bonus_periods`).
Schermen lezen hieruit; alleen de sync en de bonus-ophaling praten met AH. Dagelijks via `maintenance.daily_loop`
(`ah_sync.run_daily_once`). Nooit bestellen.

| | |
|---|---|
| `POST /api/ah/sync` | nieuwe bestellingen en kassabonnen (met bedragen) ophalen; alleen wat we nog niet hebben → `{"ok", "added", "orders", "receipts", "known", "errors", "status"}` |
| `GET /api/ah/sync/status` | `{"ok", "linked", "last_run", "trips_total", "prices_total", "bonus_periods", ...}` |
| `GET /api/bonus?period=next` | bonus van volgende week zodra AH die toont |
| `GET /api/bonus/recipes?week=` | recepten in de bonus van de periode waarin die week valt (volgende week zodra AH die toont); anders `period=current\|next` |
| `GET /api/staples` | bevat nu ook "waarschijnlijk op" (`source: "ritme"`, met `status`, `due_on`, `interval_days`) vooraan; de rest heeft `source: "vaak"`; `source_counts.waarschijnlijk_op` |
| `GET /api/week/cost?week=` | geschatte kosten van het weekmenu: `{"total", "bonus_saving", "per_meal", "meals", "unknown", "known_count", "lines", "bonus_period", "budget", "budget_pct", "actual", "actual_pct"}`; `budget` is null zonder weekbudget, `actual` = wat er die week echt is uitgegeven (null zonder ritten) |
| `GET /api/recipes/{id}/cost?persons=` | idem per recept, met `per_person` en `complete` |
| `GET /api/spend?weeks=12&detail=YYYY-MM-DD` | uitgaven per week uit `ah_trips`: `{"weeks": [{"week", "total", "discount", "trips", "unknown"}], "average_week", "average_per_person_day"}`; met `detail` ook `{"detail": {"week", "trips", "top": [10 grootste regels], "categories"}}`. Web: `/uitgaven` |
| `GET /api/replenish?week=` | "waarschijnlijk op": producten die volgens het koopritme aan de beurt zijn (≥3 keer gekocht, mediaan interval ≤120 dagen; basisvoorraad uit de recepten — olie, bloem — ≥2 keer, met `basis: true`), minus de boodschappen van de week → `{"due": [{"product_id", "name", "status": "op"\|"binnenkort", "interval_days", "last_bought", "due_on", "days_left", "avg_quantity"}], "later": [...]}` |
| `POST /api/replenish/snooze` | `{"product_id", "days": 14}` = "hebben we nog": pas weer tonen na `days` dagen |
| `POST /api/replenish/out` | `{"product_id", "name", "quantity": 1}` = "dit is op" (tijdens het koken): op het AH-lijstje en de voorspelling even met rust → `{"ok", "added"}`; zonder AH `{"ok": false, "error"}`. Alleen ouders |
| `POST /api/recipes/{id}/cheaper` | goedkopere AH-producten voor dit recept (zoekt bij AH, dus POST): `{"ok", "suggestions": [{"index", "text", "manual", "current": {…, "cost", "packs"}, "alternative": {…product…, "cost", "packs"}, "saving"}], "total_saving"}`. Wijzigt niets; kiezen = `POST /api/recipes/{id}/ingredients/{index}` met `{"text", "product": alternative}`. Alleen producten die volgens `matching.score` even goed passen en minstens € 0,20 goedkoper zijn (aantal pakken telt mee). Gaf AH bij elk ingrediënt niets terug (offline), dan `{"ok": false, "unreachable": true, "error": "AH gaf geen antwoord…"}` in plaats van "niets goedkopers". Alleen ouders |

Prijzen: bij elke zoekopdracht en elke koppeling wordt een prijssnapshot per product per dag bewaard; de kosten
gebruiken de prijs van de koppeling, anders het laatste snapshot, en de bonusprijs als het product in de bonus
van die week zit.

## Smaak per persoon

Code: `backend/app/tastes.py`, `backend/app/api/tastes.py`. Gezinsleden zijn die van `app/members.py` (tekst-ids).

| | |
|---|---|
| `GET /api/preferences` | `{"ok", "members": [{"id", "name", "role", "color", "preferences": [{"id", "member_id", "term", "kind": "dislike"\|"like"}]}], "suggestions": [{"member_id", "name", "term", "down", "up"}]}` |
| `POST /api/members/{member_id}/preferences` | `{"term": "paprika", "kind": "dislike"}` → overzicht zoals hierboven (+ `preference`); term wordt kleine letters, minimaal 2 tekens; zelfde term opnieuw zet de soort om |
| `DELETE /api/members/{member_id}/preferences/{id}` | → overzicht; 404 als het niet van dit lid is |
| `POST /api/preferences/dismiss` | `{"member_id", "term"}` = "nee, dat klopt niet": niet meer voorstellen → overzicht |

Een term matcht in de ingrediënttekst: korte termen ("ui") alleen aan het begin van een woord, termen van 5+ letters
overal ("paprika" ~ "puntpaprika's"). **Voorgestelde afkeer** (`suggestions`): een ingrediënt dat in minstens 2 recepten
zit waar die persoon netto 👎 voor gaf, en in minder dan de helft zoveel 👍-recepten. Alleen ouders mogen wijzigen.

Gebruik in de voorstellen: `POST /api/week/suggest` krijgt de redenen "Hannah lust geen paprika" / "Suze is dol op kip";
in Plannen (`propose`) krijgt een optie `avoid: ["Hannah lust geen paprika"]` en zakt ze 14 punten per persoon.
Ook de kooktijd telt mee (`app/cooktime.py`): ma–do boven 45 min gaat er af (max −20), tot 30 min +4; za/zo vanaf 60 min +4.
