# Miso

Gezins-app voor weekmenu, recepten en Albert Heijn-boodschappen. Mascotte: Miso de kat.

- `backend/` FastAPI + SQLite (web-UI in `app/templates`, JSON-API voor iOS in `app/api/json_api.py`)
- `ios/` SwiftUI-app (XcodeGen: `cd ios && xcodegen`)
- `assets/` merk: mascotte-PNG's, app-icoon; kleuren/fonts in `assets/README.md`
- `docs/ah-integratie.md` **lees dit vóór elk werk aan de AH-koppeling** (API, add-multiple-link,
  hoeveelheidsregels, basisvoorraad, voorkeursproducten)
- `docs/plan-api.md` contract van de plannings-API (planregels recept/restje/voorraad, personen, vriezer,
  besteldag); schemawijzigingen aan bestaande tabellen via `backend/app/migrations.py`
- `docs/functionele-analyse.md` wat af is, wat beter kan en in welke volgorde (stand 9 okt 2026)

## AH-koppeling: spelregels

- Nooit een AH-bestelling plaatsen of afrekenen. Lijstje vullen en mandje vullen/leegmaken mag.
- Koppelen staat in `backend/app/matching.py` (+ `_automatch` in `app/api/routes.py`). Voorkeur: biologisch
  waar mogelijk, anders AH-huismerk; basisvoorraad en keukengerei overslaan; aantal verpakkingen rekenen.
- Handmatige keuzes (`manual: true`) nooit automatisch overschrijven. Verhoog `MATCH_VERSION` als de
  regels veranderen, zodat oude koppelingen opnieuw gedaan worden.
- Maatstaf voor kwaliteit: AH's eigen "Productsuggesties" bij Allerhande-recepten.

## Testen

```
cd backend && DATABASE_URL=sqlite:////tmp/t.db python -m pytest -q        # offline, verplicht groen
LIVE_AH=1 python -m pytest -q -m live                                        # echte AH-API
```

`tests/data/ingredient_lines.txt` zijn echte ingrediëntregels uit de recepten; elke fout die je vindt
wordt een test. GitHub Actions draait de tests bij elke push en wekelijks de live-tests.

## Verbeterlus koppelen (gauntlet)

1. Meten tegen AH's eigen keuzes: `python -m tools.eval_bar` (offline, cache) of `--live` (vernieuwt
   `tests/data/ah_bar_search_cache.json`). Maatstaf = `tests/data/ah_bar.txt` (AH "Productsuggesties" van
   Allerhande-recepten). `tests/test_bar_benchmark.py` bewaakt de drempels; verhoog ze als de score stijgt.
2. Blinde criticus: zet onze lijst en AH's lijst per recept zonder labels naast elkaar en laat een aparte
   agent kiezen + grootste gat noemen. Los het gat op, meet opnieuw, herhaal tot onze lijst wint.
3. Eigen recepten: `/dekking` (en `/api/coverage`, `POST /api/coverage/refresh`) toont per recept wat er
   gekoppeld/open/overgeslagen is. Handmatige keuzes worden geleerde voorkeuren (`product_preferences`).

## Deploy

Portainer-stack `miso` (NAS 192.168.68.120) haalt `main` elke 5 minuten op (GitOps polling).
Web/API: poort 9927. Eenmalige AH-inlogproxy: poort 9928 (`/start`).
