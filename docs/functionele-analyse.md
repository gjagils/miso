# Functionele analyse Miso (9 oktober 2026)

Stand van zaken na 56 commits in twee dagen. Wat is af, wat kan beter, en in welke volgorde.
Verwijzingen zijn naar bestanden in deze repo; regelnummers kloppen op de datum hierboven.

## Status na opvolging (9 oktober, avond)

Opgepakt: A1 (iOS koppelen + Ontbrekend), A2 (recept bewerken/verwijderen, web-JSON + iOS), A3 (week-sync leest
het echte AH-lijstje; mandje per bestelling), A4 (Kiezen stap 3 web + iOS), A5 (vriezer volgt kook dubbel),
A6 (profielen bij import + dagelijks), A7 (iOS uitloggen bij 401), A8 (herinnering na inplannen), A9
(bevestigen bij verwijderen), A10 (geen stil eerste product), A11 deels (zoekveld Recepten), B (dode code,
`/allerhande`, lock-flag, naam Miso/versie 1.1, foto's lokaal, opruimen bij verwijderen), C2 (tempo-limiet,
backoff, zoekcache, half zoveel calls), C5 deels (vertraging JSON-login), C6 (geen dubbele schaling).
Back-up: dagelijks in `data/backups` (zelfde schijf; neem de datamap mee in Hyper Backup).

Nog open: tokens versleutelen (vraagt een geheime sleutel als omgevingsvariabele), C3 (gedeelde
AH-client bij gelijktijdige gebruikersacties), C4 (zware GET's), C7-C11, weeknavigatie op Vandaag,
`POST /api/plan` (oude route, alleen nog door tests gebruikt), gedupliceerde helpers.

## Kort oordeel

De kern, van recept naar weekmenu naar AH-lijstje, is compleet en werkt op web én iOS. De kwaliteit van de
AH-koppeling wordt gemeten in plaats van gegokt. Wat beter kan zit in drie hoeken:

1. Functionaliteit die op web bestaat maar niet in iOS.
2. Boekhouding die uit de pas kan lopen met de werkelijkheid bij AH.
3. Dingen die half af zijn, plus een paar operationele risico's.

## Wat er is

### Web (`backend/app/templates`)

| Pagina | Wat je er doet |
|---|---|
| Vandaag `/` | Deze week lezen, naar kookmodus, banner "volgende week" met plannen of Miso laten voorstellen |
| Recepten `/recepten` | Importeren (URL, tekst, foto's), filters "zonder foto" en "zonder AH-product" |
| Recept `/recipe/{id}` | Inplannen, kookmodus, foto wijzigen, glutenvrij, ingrediënten koppelen aan AH, op lijstje zetten, verwijderen |
| Kiezen `/kiezen` | 3 stappen: kiezen (eigen + Allerhande + bonus) → inplannen → boodschappen (lijstje, mandje, AH-lijsten, standaardboodschappen) |
| Weekmenu `/weekmenu` | Per dag toevoegen, verplaatsen, verwijderen; boodschappenstatus; vriezer; gezond en gevarieerd |
| Dekking `/dekking` en Ontbrekend `/dekking/ontbrekend` | Koppelkwaliteit over alle recepten, open ingrediënten per zoekterm kiezen of uitvinken |
| Instellingen `/settings` | Gezin en besteldag, weergave, AH koppelen, AH-favorieten importeren, Mealie-import |

### iOS (`ios/AHRecepten`)

Vijf tabs: Vandaag, Wat eten we? (Kiezen in 3 stappen), Recepten, Weekmenu, Meer. Daarnaast receptdetail,
kookmodus, import, vriezer, en één gedeeld inplan-blad (`PlanSheet`) voor plannen, kook dubbel en verplaatsen.
Share-extensie "Deel naar Miso" leest de pagina op het toestel uit en stuurt tekst, bronlink en foto naar
`/api/import`. Lokale herinnering de avond voor de besteldag.

### Backend (`backend/app`)

- Planning: regels per dag (recept, restje, voorraad), personen per regel met geschaalde boodschappen, kook
  dubbel (morgen of vriezer), vriezerporties, besteldag, weekstatus als delta tegen het AH-lijstje.
  Contract in `docs/plan-api.md`.
- AH: anoniem zoeken (GraphQL + REST), gebruikerslogin via code of proxy, lijstje, mandje (alleen bij actieve
  bestelling), bonus, favorietenlijsten, kassabonnen en bestellingen voor standaardboodschappen. Nooit
  bestellen of afrekenen.
- Koppelen: `matching.py`, `MATCH_VERSION = 22`, voorkeur bio dan huismerk, verpakkingen rekenen, geleerde
  voorkeuren. Benchmark tegen AH's productsuggesties (`tests/test_bar_benchmark.py`) en 100 eigen cases.
- Gezondheid: profiel per recept door Claude (kcal, groente, eiwit, basis, keuken, Schijf van Vijf),
  regelgebaseerde weeksignalen, deterministisch voorstel voor lege dagen.
- Import: URL, tekst, foto's (Claude), Allerhande, AH-favorieten, Mealie, share-extensie.
- Auth: één gezins-PIN, vast HMAC-token als cookie of Bearer.

## Wat goed is

- **De hoofdflow is af en logisch.** Kiezen → inplannen → boodschappen, met één inplan-dialoog die overal
  hergebruikt wordt en één primaire knop ("Zet N nieuwe producten op je AH-lijstje").
- **Planningsmodel is rijker dan de meeste menu-apps.** Personen per regel, restjes die meeschuiven,
  vriezerporties die automatisch af- en bijgeboekt worden, besteldag met countdown en herinnering.
- **AH-koppeling is het paradepaardje.** 22 matchrondes, verpakkingen rekenen, leren van handmatige keuzes,
  en een benchmark met drempels in CI. Dat is zeldzaam.
- **Import is breed.** Zeven bronnen, en de share-extensie omzeilt sites die scrapers blokkeren.
- **Gezond en gevarieerd** is een slimme laag met weinig code.
- **Ontbrekend en Dekking** maken koppelkwaliteit zichtbaar en verbeterbaar vanuit de UI.
- **Veiligheidsregel wordt nageleefd.** Nergens wordt besteld; de code zegt dat expliciet.
- **Tests:** 12 testbestanden, ruim 100 tests, 726 echte ingrediëntregels als regressieset, CI bij elke push
  plus wekelijkse live-test. iOS heeft logica- en decodeertests.

## Wat beter kan

### A. Functioneel, merkbaar voor de gebruiker

1. **iOS mist het koppelen van ingrediënten.** Twee hints in de app verwijzen naar iets wat de app niet kan
   (`ios/AHRecepten/Kiezen/KiezenShopView.swift:77`, `ios/AHRecepten/Planning/Week/GroceriesSection.swift:55`).
   Alleen web heeft de ingrediënteneditor, Ontbrekend, foto wijzigen, glutenvrij handmatig en verwijderen.
   Grootste gat tussen de clients.
2. **Recepten zijn niet te bewerken.** Geen endpoint voor naam, porties, tijd, bereiding of ingrediënttekst.
   Een extractiefout blijft staan. Verwijderen is alleen een webformulier (`backend/app/api/routes.py:335`).
3. **Boodschappenboekhouding gaat uit van een AH-lijstje dat alleen Miso aanpast.**
   - `CartPush` per week groeit alleen; haalt iemand iets uit het lijstje in de AH-app, dan denkt Miso dat het
     er nog op staat (`routes.py:700-708`).
   - "Zet op AH-lijstje" op de receptpagina (`/api/cart/fill`) registreert niets, dus een week-sync erna zet
     dubbel (`routes.py:819-851`).
   - `BasketPush` is globaal in plaats van per bestelling (`backend/app/models.py:137-145`); na een geplaatste
     bestelling trekt "leegmaken" af van het volgende mandje.
4. **Kiezen stap 3 toont iets anders dan het verstuurt.** Lijst en aantal komen van de gekozen recepten
   (ook die op "niet inplannen"), maar de knop synct de hele week inclusief al geplande dagen en
   voorraadextra's (`backend/app/templates/kiezen.html:368,448,573,645`; iOS idem). Met AH-token klopt de tekst
   "komen wel in je boodschappen" niet.
5. **Vriezer loopt uit de pas bij kook dubbel.** Het vriezeritem wordt al bij inplannen aangemaakt
   (`backend/app/api/plan.py:153-158`). Regel verwijderen, verplaatsen of personen wijzigen past het item niet
   aan (`plan.py:229-251`).
6. **Voorstellen werken alleen voor recepten die ooit gepland zijn.** Profielen ontstaan pas bij het openen van
   de gezondheidspagina. `POST /api/profiles/refresh` bestaat (`backend/app/api/health.py:91`) maar geen UI
   roept het aan. Nieuwe imports doen dus niet mee met "Laat Miso voorstellen".
7. **Verlopen sessie op iOS wordt niet afgevangen.** Een 401 geeft alleen een melding
   (`ios/AHRecepten/API.swift:43`); de gebruiker moet zelf uitloggen via Meer.
8. **Herinnering herhaalt niet.** Eén notificatie, alleen opnieuw gepland als de app geopend wordt. Inplannen
   vanaf receptdetail of vriezer ververst hem niet (`ios/AHRecepten/RecipeDetailView.swift:117`,
   `ios/AHRecepten/Planning/Freezer/FreezerView.swift:66`).
9. **Verwijderen zonder bevestiging** op iOS Weekmenu, behalve als er restdagen zijn
   (`ios/AHRecepten/PlanView.swift:155-162`).
10. **Receptpagina "Zoek" kiest stilzwijgend het eerste resultaat** voordat je iets aanklikt
    (`backend/app/templates/recipe_detail.html:158`).
11. **Geen zoekveld op de webpagina Recepten** en geen weeknavigatie op Vandaag (web en iOS).

### B. Dubbelingen en losse eindjes

- Drie weekweergaven op iOS (Vandaag, Weekmenu, Kiezen stap 2); Kiezen bouwt de weeknavigatie zelf in plaats
  van `WeekNavigator` te gebruiken (`KiezenPlanView.swift:33-50`).
- Drie receptzoekers op iOS met verschillende debounce en limieten (KiezenView, PlanSheetModel, RecipesView).
- Dode code: `ios/AHRecepten/RecipePicker.swift`, `API.savePlan` met de oude `POST /api/plan`
  (`API.swift:166`, `routes.py:621`), de pagina `/allerhande` zonder enige link.
- "Week vastzetten" wordt opgeslagen maar nergens gebruikt of getoond; iOS Kiezen stuurt wel `locked: true`
  (`KiezenShopView.swift:299`), tegen `docs/plan-api.md:161-164` in.
- Twee codepaden naar hetzelfde sync-endpoint op iOS (`syncWeek` en `pushWeekToList`).
- Naamgeving nog half "AH Recepten": FastAPI-titel (`main.py:23`), user-agent (`extractor.py:138`), database
  `ahcommunicator.db` (`config.py:7`), iOS-target en `ios/README.md`. Versie 1.0 in Info.plist versus 0.1 in
  `project.yml`.
- Gedupliceerde helpers: `routes._get_setting`/`_set_setting` naast `planning.get_setting`/`set_setting`;
  `health._week` naast `planning.week_entries`.
- Recept verwijderen laat `RecipeProfile` en `FreezerItem.from_recipe_id` achter.
- URL- en Allerhande-imports houden een externe foto-link; alleen uploads, share, Mealie en foto-vervangen
  slaan lokaal op (`routes.py:310,896`).

### C. Robuustheid en risico

1. **AH-tokens en Mealie-token staan plaintext in SQLite** (`backend/app/ah_login_proxy.py:108`,
   `routes.py:999`). Geen back-up van de datamap: recepten, foto's, plan en geleerde voorkeuren in één map.
2. **Geen rate limiting, backoff of cache richting AH.** Tot 7 zoekopdrachten per ingrediënt, altijd ook REST
   naast GraphQL (`backend/app/clients/ah.py:178`), alleen een semafoor van 4. "Alles opnieuw koppelen" doet
   dat voor alle recepten in één burst (`backend/app/api/shopping.py:122-143`). Met een onofficiële API en
   gespoofde app-versie is dit het grootste operationele risico.
3. **Globale AH-client met per-request tokens** (`ah.py:431`; `set_user_tokens` in `routes.py:690`,
   `shopping.py:181`). Gelijktijdige requests kunnen elkaars refresh-token overschrijven.
4. **GET's met zware bijwerkingen.** Recept openen kan tot 25 s AH-calls doen (`json_api.py:57`,
   `routes.py:518`); de gezondheidspagina roept Claude aan (`health.py:40`). Mealie-import draait synchroon in
   de request.
5. **Login-proxy draait permanent** en is zonder `APP_PIN` een open proxy naar login.ah.nl
   (`ah_login_proxy.py:49-52`). JSON-login heeft geen vertraging bij een foute pincode (`json_api.py:31`).
   Het sessietoken verloopt nooit en is alleen in te trekken door de PIN te wijzigen.
6. **Matching gebruikt hard 4 personen** voor "per persoon" en HelloFresh-reeksen (`matching.py:91`), los van
   de huishoudinstelling en de schaling per regel. Kan dubbel schalen.
7. **LLM-antwoord wordt blind gelezen** in extractie en glutenvrij-voorstel (`extractor.py:206,250`);
   gezondheidsprofiel valt stil terug op "vlees" en 600 kcal bij ongeldige output (`nutrition.py:43-60`).
   Profielen verouderen niet als ingrediënten wijzigen.
8. **Achtergrondtaken in module-globals** (`shopping.py:119`, `health.py:19`): weg bij herstart, alleen correct
   met één worker.
9. **Benchmark-drempels liggen 1 punt onder de huidige score** en de offline-eval gaat stilletjes live voor
   zoektermen die niet in de cache staan (`backend/tools/eval_bar.py:90`).
10. **Afhankelijkheden:** `anthropic==0.42.0` gepind tegen een nieuw model-id; CI installeert
    `requirements-dev.txt` niet; geen lint of iOS-CI.
11. **Matchregels groeien per geval.** Circa 30 handmatige woordenlijsten met zo'n 1.200 strings in
    `matching.py`; overlap tussen lijsten begint te ontstaan. De benchmark is het enige vangnet.

## Aanbevolen volgorde

1. **Back-up van de datamap en tokens uit plaintext.** Laag werk, hoog risico weg.
2. **Zoekcache plus throttling in de AH-client.** Beschermt het account en maakt recept openen snel.
3. **Ingrediënten koppelen en uitvinken in iOS**, zodat de app zijn eigen hints waarmaakt.
4. **Kiezen stap 3 eerlijk maken:** óf de weekdelta tonen, óf alleen de gekozen recepten syncen. Daarna de
   boekhouding corrigeren door het AH-lijstje te lezen vóór een sync in plaats van op `CartPush` te
   vertrouwen; `cart/fill` laten registreren; `BasketPush` per bestelling.
5. **Opruimen:** dode code, `/allerhande`, lock-flag, naamgeving, en profielen aanmaken bij import zodat
   voorstellen alle recepten meenemen.
6. **Recept bewerken** (web en iOS) en sessieverloop afvangen op iOS.
