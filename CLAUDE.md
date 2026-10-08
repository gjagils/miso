# Miso

Gezins-app voor weekmenu, recepten en Albert Heijn-boodschappen. Mascotte: Miso de kat.

- `backend/` FastAPI + SQLite (web-UI in `app/templates`, JSON-API voor iOS in `app/api/json_api.py`)
- `ios/` SwiftUI-app (XcodeGen: `cd ios && xcodegen`)
- `assets/` merk: mascotte-PNG's, app-icoon; kleuren/fonts in `assets/README.md`
- `docs/ah-integratie.md` **lees dit vóór elk werk aan de AH-koppeling** (API, add-multiple-link,
  hoeveelheidsregels, basisvoorraad, voorkeursproducten)

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

## Deploy

Portainer-stack `miso` (NAS 192.168.68.120) haalt `main` elke 5 minuten op (GitOps polling).
Web/API: poort 9927. Eenmalige AH-inlogproxy: poort 9928 (`/start`).
