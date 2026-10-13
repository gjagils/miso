# Plan: AH-data als grondstof, Miso's eigen logica erbovenop

Stand 13 oktober 2026. AH ligt plat door een cyberincident, dus niets hieronder is live getest. Het plan is
zo opgezet dat het meeste nu gebouwd kan worden tegen vastgelegde voorbeeldantwoorden, en dat er één korte
live-sessie nodig is zodra AH terug is.

Uitgangspunt: we bouwen de AH-app niet na. AH levert bonus, bestellingen, kassabonnen, prijzen en
productdata. Miso legt daar eigen logica op: wat koken we, wat kost het, wat is waarschijnlijk op, wat
vindt het gezin lekker. Nooit bestellen of afrekenen; dat blijft de harde grens.

## 1. Wat AH ons geeft (bouwstenen)

Bronnen: de jabbink-gist, SupermarktConnector, ah-mcp en vooral `gwillem/appie-go`, waar ah-mcp op bouwt.
Die repo bevat een volledige API-catalogus uit de iOS-app 9.28 en een GraphQL-schemadump (januari 2026).
Zie de bronverwijzingen onderaan.

| Bouwsteen | Wat het geeft | Status in Miso |
|---|---|---|
| Bonus per periode | Alle nationale aanbiedingen, bonusgroepen, mechanisme ("2 voor 5.50", "1+1"), persoonlijke bonus, Bonus Box, startdatum en einddatum. Volgende periode is enkele dagen vooraf zichtbaar. | Aanwezig: `fetch_bonus`, `score_recipes`, cache per periode |
| Bestellingen met bedragen | `orderFulfillments(CLOSED)` geeft per bestelling `totalPrice` (voor en na korting, korting) en `costOverview` (netto, totale bonuskorting). `order(id)` geeft een volledige bon met regels en totalen. `orderReport` aggregeert over bestellingen per product. | Alleen productnaam en aantal gelezen, geen bedragen |
| Kassabonnen met regels | `posReceiptDetails`: per regel prijs, regelbedrag, aantal of gewicht, bonusmarkering; per bon kortingen, totaal, winkel, datum. Kassabon-ids naar webshop-ids via `productConvertId`. | Alleen productnaam gelezen |
| Prijs van een hypothetisch mandje | GraphQL `totalPrice(products: [{id, quantity}])` geeft bedrag zonder korting en korting. | Niet gebruikt |
| Productdetail | Voedingswaarden per 100 g, ingrediënten, allergenen, prijs per eenheid, taxonomie, beschikbaarheid, alternatieven (`productAlternatives`, `otherSorts`). | Alleen zoekresultaten gebruikt |
| Eerder gekocht | `isPreviouslyBought` per product, `sortOn=PURCHASE_FREQUENCY` in zoeken, `productPurchaseHistory`, `searchPreviouslyBought`. Geen veld met frequentie of laatste aankoop; dat moeten we zelf afleiden uit bestellingen en bonnen. | Deels: standaardboodschappen uit laatste 20 ritten |
| AH's eigen aanbevelingen | `recommendations/dontforgetlane`, `recommendationsForgottenProducts`, `recommendationsMissingBonus` ("koop er 1 bij voor de bonus"), `recipeBonusLane` (koken met bonus), `productCrossSellsV2`. | Niet gebruikt |
| Allerhande | Zoeken, recept met ingrediënten, voedingswaarden, AH's eigen productsuggesties per recept (`recipeProductSuggestionsV2`). | Zoeken en recept aanwezig; productsuggesties zijn onze benchmark |
| Lidmaatschap | Koopzegels, Premium-besparing (`subscriptionPremiumSavingsV2`), favoriete winkel. | Niet gebruikt |

Wat ontbreekt en wat we daarmee doen:

- **Prijshistorie bestaat niet.** Miso legt zelf prijzen vast bij elke zoekopdracht en bonus-ophaling.
- **Koopfrequentie per product is geen veld.** We berekenen het zelf uit bestellingen plus bonnen. Dat doet
  ah-mcp ook zo.
- **Argumenten van schema-only queries** (`orderReport`, `order(id)`, `productPurchaseHistory`,
  `totalPrice`) zijn niet gedocumenteerd. Eén live-sessie met logging lost dat op. Tot die tijd gebruiken we
  de REST-bestelregels (prijs per regel staat erin) en `orderFulfillments` (totalen staan erin), die wel
  gedocumenteerd zijn.
- **Geen push vanuit AH.** Alles is pollen. Een dagelijkse sync-job is genoeg.

## 2. Fundament: een lokale AH-datalaag

Alles hieronder leunt op dezelfde drie tabellen. Dit is het eerste wat gebouwd wordt en het kan nu, want
het is datamodel, parsers tegen voorbeeldantwoorden en een sync-job met cache en throttling.

| Tabel | Inhoud | Gevuld door |
|---|---|---|
| `ah_trips` | Eén rij per bestelling of kassabon: datum, bron, winkel, totaal, korting. Per regel: product-id, naam, aantal, prijs, regelbedrag, bonus ja/nee. | Dagelijkse sync van `orderFulfillments(CLOSED)` plus orderdetails, en `posReceiptsPage` plus details. Alleen nieuwe ritten ophalen. |
| `ah_prices` | Snapshot per product per datum: prijs, prijs voor bonus, bonusmechanisme, eenheidsprijs. | Elke zoekopdracht en elke bonus-ophaling schrijft erin. |
| `ah_bonus_periods` | Periode (start, eind) met de bonusproducten en groepen. | Bestaande `fetch_bonus`, nu ook de volgende periode zodra zichtbaar. |

Spelregels voor de datalaag:

- Eén `AHSync`-module met cache per endpoint, backoff bij 429, en een semafoor. Geen enkel scherm roept
  AH rechtstreeks aan; schermen lezen uit de tabellen. Dat lost meteen de huidige "GET met 25 seconden
  AH-calls" op.
- Elke parser krijgt een fixture uit echte antwoorden. `appie-go` heeft testdata (`order_details.json`,
  bonus, kassabon); licentie checken en overnemen waar dat mag. Bij de live-sessie leggen we eigen
  antwoorden vast, geanonimiseerd.
- Een status-pagina onder Instellingen: laatste sync, aantal ritten, aantal prijzen, fouten.

## 3. De thema's

### A. Bonus-slim koken

Doel: elke week weten welke eigen recepten nu goedkoop zijn en daar het weekmenu op sturen, zonder dat het
menu eenzijdig wordt.

- **Recepten in de bonus.** Bestaat al als ranking (`score_recipes`). Uitbreiden met: besparing per
  recept in euro's, aantal bonusproducten, en een lijst op de Kiezen-pagina en in iOS.
- **Volgende periode meenemen.** De besteldag is zondag, de bonus begint maandag. De volgende periode is
  enkele dagen eerder zichtbaar, dus plannen voor volgende week gebeurt met de bonus die dan geldt. Dat
  vraagt alleen een tweede `fetch_bonus` met de volgende startdatum.
- **Bonus als signaal in het voorstel.** De voorstelfunctie krijgt een bonus-term in de score, naast
  gezondheid en variatie. Uitlegbaar: "in de bonus, scheelt €3,20".
- **"Koop er één bij".** AH's `recommendationsMissingBonus` zegt wanneer je net onder een
  2-voor-aanbieding zit. Tonen in het boodschappenoverzicht als tip, met één knop om het aantal te
  verhogen.
- **Vrijdagbericht.** Lokale notificatie "4 van je recepten zijn volgende week in de bonus", als de
  volgende periode zichtbaar is.
- **Persoonlijke bonus en Bonus Box.** Eerst alleen tonen bij producten die in het weekmenu zitten.
  Activeren via de mutatie is mogelijk maar komt later; het is een schrijfactie op het AH-account.

### B. Uitgaven en budget

Doel: weten wat eten kost, vooraf en achteraf, en concrete manieren zien om het omlaag te krijgen.

- **Uitgavenoverzicht.** Per week en per maand uit `ah_trips`: totaal, bonuskorting, aantal ritten,
  bedrag per persoon per dag. Trendlijn over de laatste 12 weken. Onderscheid bezorgd versus winkel.
- **Waar ging het geld heen.** Per week de top-10 regels en per categorie (AH-taxonomie staat op elke
  regel). Dit beantwoordt "waarom was deze week duur".
- **Kosten van het weekmenu vooraf.** Som van de gekoppelde producten maal verpakkingen, met bonus. Prijs
  per recept en per portie op de receptpagina. Later via `totalPrice` voor de exacte korting.
- **Goedkoper alternatief.** Per gekoppeld product: huismerkvariant, bonusvariant, of grotere verpakking
  bij meerdere recepten. Eerst met onze eigen zoekresultaten, daarna met `productAlternatives`.
- **Weekbudget.** Een instelling "doel per week" en een balk op Weekmenu: geschat versus doel, achteraf
  werkelijk versus doel.
- **Premium.** Alleen tonen wat AH zelf rapporteert als besparing, zodat de keuze om Premium te houden
  onderbouwd is.

### C. Voorraad, licht

Doel: "moet ik wc-papier of shampoo bestellen?" beantwoorden zonder iets bij te houden.

Het marktonderzoek is hier eenduidig: volledige voorraadadministratie (Grocy) houdt niemand vol. Wat wel
werkt is wat AH zelf doet met "Maak compleet": voorspellen uit koopgedrag. Daarom:

- **Herbestel-voorspelling.** Per product uit `ah_trips`: gemiddeld interval tussen aankopen, laatste
  aankoop, gemiddelde hoeveelheid. Een product is "waarschijnlijk op" als laatste aankoop plus interval
  binnen de komende week valt. Minimaal 3 aankopen nodig voor een voorspelling.
- **Tonen op de besteldag.** Een blok "Waarschijnlijk op" in het boodschappenoverzicht en de banner:
  per product "toevoegen" of "hebben we nog". Het antwoord schuift de voorspelling op; geen boeking.
- **Basisvoorraad uit recepten.** De ingrediënten die we nu overslaan (zout, olie, bloem) koppelen aan
  hetzelfde mechanisme: olijfolie die je lang niet kocht komt op de lijst "waarschijnlijk op".
- **"Op"-knop.** In kookmodus en op het product: markeer iets als op. Dat is de enige handmatige actie, en
  die zet het product direct op de lijst voor de volgende bestelling.
- **AH's signaal erbij.** `dontforgetlane` en `recommendationsForgottenProducts` als extra kandidaten, met
  label "AH denkt dat je dit vergeet".
- Later, optioneel: houdbaarheid voor verse producten uit `minBestBeforeDays`, alleen om te waarschuwen
  dat iets in de vriezer of koelkast op moet.

### D. Gezin en kinderen

Doel: het gezin kiest mee, en Miso leert wat iedereen lekker vindt.

Het huishouden is nu een getal. Dit thema maakt er personen van. Dat is de basis voor alles hieronder.

- **Personen.** Tabel `household_members`: naam, kind ja/nee, kleur of avatar. Planregels krijgen
  optioneel "wie eet mee" naast het aantal.
- **Beoordelen na het eten.** De dag na een gekookt recept vraagt Vandaag: "Hoe was de lasagne?" met per
  persoon duim omhoog, neutraal, duim omlaag, en een notitie. Opslaan in `meal_ratings` met entry,
  recept, persoon, datum. Dit is volgens het marktonderzoek het grootste gat in Miso.
- **Voorkeuren en afkeer per persoon.** Op ingrediëntniveau: "lust geen paprika", "wil olijven proberen".
  Deels handmatig, deels afgeleid: drie keer duim omlaag bij recepten met paprika geeft een suggestie
  "Noor lust waarschijnlijk geen paprika, klopt dat?".
- **Wensenlijst.** Een PIN-loos kinderscherm op de iPad of telefoon: kaarten met foto's van recepten,
  kind tikt een hartje. Wensen verschijnen bij Kiezen als "Noor wil dit" en tellen mee in het voorstel.
  Technisch: een apart token met alleen lees- en wensrechten.
- **Stemmen.** Ouder zet 8 kandidaten klaar, iedereen stemt, de uitslag vult de lege dagen. Dit is de
  BiteBallot-aanpak en kan op dezelfde kindertoken.
- **Kids-kookavond.** Tag "makkelijk met kinderen" op recepten, een vaste dag in de instellingen, en het
  voorstel vult die dag alleen met recepten met die tag.

### E. Aanbevelen: één uitlegbare score

Doel: alle signalen samenbrengen in één voorstelfunctie die uitlegt waarom.

De voorstelfunctie bestaat (gezondheid, variatie, 14 dagen niet gekookt). Die wordt uitgebreid tot een
score met gewogen termen:

| Signaal | Bron | Thema |
|---|---|---|
| Gezond en gevarieerd | bestaand profiel | bestaand |
| Lang niet gekookt | planregels | bestaand |
| In de bonus, besparing | `ah_bonus_periods` | A |
| Kosten per portie versus budget | `ah_prices` | B |
| Beoordelingen van wie meeëet | `meal_ratings` | D |
| Wensen en afkeer van wie meeëet | `household_members` | D |
| Past bij de dag: kooktijd doordeweeks, kids-avond | instellingen | D |
| Gebruikt wat we al hebben: restjes, vriezer, waarschijnlijk-nog-niet-op | vriezer, C | C |

Elke suggestie krijgt een regel uitleg: "In de bonus (−€2,80), favoriet van Noor, 5 weken geleden". Als
Miso het goed doet, voelt de voorstelknop als een gezinslid dat meedenkt, niet als een willekeurige
generator. Productaanbevelingen volgen dezelfde lijn: "vergeet je niet" is standaardboodschappen plus
waarschijnlijk-op plus AH's eigen vergeet-signaal, met bron erbij.

### F. Van populaire apps overnemen

Uit het marktonderzoek, bewust klein gehouden:

- **Kooklijst** ("wil ik binnenkort maken") en **herbruikbare weken** ("sla deze week op"). Klein, veel
  gebruikt, goede input voor het voorstel.
- **Kookstand plus.** Timers herkennen in de stappen ("20 minuten" wordt een knop), hoeveelheid van het
  ingrediënt in de stap tonen.
- **Koken met wat er is.** Restjes plus vriezer plus waarschijnlijk-nog-in-huis matchen tegen eigen
  recepten. Eerst regelgebaseerd. Foto van de koelkast is een latere stap.
- Niet doen: volledige voorraad, sociaal of community, gangpadvolgorde, spraak.

## 4. Aanpak nu AH plat ligt

**Fase 0, nu.** Alles wat zonder AH kan:

1. Datalaag: tabellen, migraties, parsers tegen fixtures, sync-module met cache en throttling. Fixtures uit
   appie-go en de eigen gist-voorbeelden.
2. Personen, beoordelingen, voorkeuren, wensen: volledig offline te bouwen, inclusief UI.
3. Uitgavenoverzicht en herbestel-voorspelling: logica en schermen tegen een gevulde testdatabase.
4. Voorstelscore: nieuwe termen met gewichten, testbaar met vaste data.
5. Kooklijst, herbruikbare weken, kookstand-timers.

**Fase 1, zodra AH terug is.** Eén live-sessie van een uur met logging aan:

1. Headers en tokens checken; `appie-ios` als clientId geeft tokens van 7 dagen in plaats van 2 uur.
2. De schema-only queries proberen: `orderFulfillments` met `totalPrice` en `costOverview`, `order(id)`,
   `totalPrice(products)`, `productPurchaseHistory`, `recommendationsMissingBonus`, `dontforgetlane`.
   Werkende antwoorden als fixtures vastleggen.
3. Eerste volledige sync van bestellingen en bonnen draaien. Daarna gaan de schermen van fase 0 vanzelf
   werken.

**Fase 2.** Bonus-slim koken en budget aanzetten, dan voorraad, dan gezin en aanbevelen in de
weekpraktijk tunen met echte beoordelingen.

## 5. Backlog

**Definition of Done** (geldt voor elk item): app en website samen bij, tests groen, backlog in dit document
bijgewerkt, `docs/plan-api.md` en `CLAUDE.md` bijgewerkt, de handleiding (`/hulp`) bijgewerkt. Zie `CLAUDE.md`.

Prioriteit: 1 eerst. Grootte: S is een dagdeel, M een dag of twee, L meer. Offline: te bouwen en te
testen zonder AH.

### Fundament

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| F1 | Tabellen `ah_trips`, `ah_prices`, `ah_bonus_periods` plus migraties | S | ja | 1 | ✅ |
| F2 | Parsers voor orderdetails, `orderFulfillments`, `posReceiptDetails` met prijzen; fixtures | M | ja | 1 | ✅ |
| F3 | `AHSync`-module: cache per endpoint, backoff bij 429, semafoor, alleen nieuwe ritten | M | ja | 1 | ✅ |
| F4 | Prijssnapshot schrijven bij elke zoekopdracht en bonus-ophaling | S | ja | 1 | ✅ |
| F5 | Sync-statusblok op Instellingen; dagelijkse job | S | ja | 2 | ✅ |
| F6 | Live-sessie: schema-only queries proberen, fixtures vastleggen, clientId `appie-ios` | M | nee | 1 zodra AH terug | ⏳ wacht op AH |
| F7 | Bestaande schermen van directe AH-calls afhalen; lezen uit de datalaag | M | ja | 2 | deels (bonus, kosten, uitgaven, ritme lezen uit de datalaag) |

### A. Bonus-slim koken

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| A1 | Volgende bonusperiode ophalen en tonen zodra zichtbaar | S | ja | 1 | ✅ |
| A2 | "Recepten in de bonus" met besparing in euro's op Kiezen, web en iOS | M | ja | 1 | ✅ web + iOS |
| A3 | Bonus-term in de voorstelscore met uitleg | S | ja | 2 | ✅ |
| A4 | "Koop er één bij" uit `recommendationsMissingBonus` in het boodschappenoverzicht | M | na F6 | 3 | ⏳ na F6 |
| A5 | Vrijdagbericht "N recepten in de bonus volgende week" | S | ja | 3 | open |
| A6 | Persoonlijke bonus en Bonus Box tonen bij producten in het weekmenu | M | na F6 | 4 | ⏳ na F6 |

### B. Uitgaven en budget

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| B1 | Uitgavenpagina: per week en maand, bonuskorting, per persoon per dag, 12-weken-trend | M | ja | 1 | ✅ web + iOS |
| B2 | Top-10 regels en kosten per categorie per week | S | ja | 2 | ✅ web + iOS |
| B3 | Geschatte kosten van het weekmenu en prijs per portie op het recept | M | ja | 1 | ✅ web + iOS |
| B4 | Goedkoper alternatief per gekoppeld product | M | ja | 2 | ✅ web + iOS |
| B5 | Weekbudget-instelling met balk geschat versus doel versus werkelijk | S | ja | 3 | ✅ web + iOS |
| B6 | Premium-besparing tonen uit `subscriptionPremiumSavingsV2` | S | na F6 | 4 | ⏳ na F6 |

### C. Voorraad, licht

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| C1 | Herbestel-voorspelling per product: interval, laatste aankoop, hoeveelheid | M | ja | 1 | ✅ |
| C2 | Blok "Waarschijnlijk op" op besteldag met toevoegen of hebben-we-nog; antwoord schuift voorspelling op | M | ja | 1 | ✅ web + iOS |
| C3 | Basisvoorraad uit recepten koppelen aan de voorspelling | S | ja | 2 | ✅ |
| C4 | "Op"-knop in kookmodus en op product | S | ja | 2 | ✅ web + iOS |
| C5 | AH's vergeet-signalen als extra kandidaten met bronlabel | S | na F6 | 3 | ⏳ na F6 |
| C6 | Houdbaarheidswaarschuwing voor vriezer en koelkast | M | ja | 4 | ✅ vriezer web + iOS; koelkast open |

### D. Gezin en kinderen

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| D1 | Tabel `household_members`; personen beheren in Instellingen; "wie eet mee" op planregel | M | ja | 1 | vervalt (main: Wie ben jij?) |
| D2 | Beoordelen na het eten op Vandaag, per persoon; tabel `meal_ratings` | M | ja | 1 | vervalt (main: Lekker? per persoon) |
| D3 | Voorkeuren en afkeer per persoon op ingrediëntniveau, handmatig | M | ja | 2 | ✅ web + iOS |
| D4 | Afkeer afleiden uit beoordelingen met bevestigingsvraag | M | ja | 3 | ✅ web + iOS |
| D5 | Kindertoken met alleen lees- en wensrechten | S | ja | 2 | vervalt (main: rol kind) |
| D6 | Wensenlijst-scherm voor kinderen; wensen bij Kiezen en in het voorstel | M | ja | 2 | vervalt (main: wensen) |
| D7 | Stemmen op kandidaten; uitslag vult lege dagen | M | ja | 3 | open |
| D8 | Tag "makkelijk met kinderen" en vaste kids-kookavond | S | ja | 3 | open |

### E. Aanbevelen

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| E1 | Voorstelscore herschrijven als gewogen termen met uitlegregel per suggestie | M | ja | 1 | ✅ |
| E2 | Termen: beoordelingen, wensen, afkeer, kooktijd per weekdag, kids-avond | M | ja | 2 | ✅ kooktijd; kids-avond open |
| E3 | Termen: bonus, kosten per portie, gebruikt restjes en vriezer | S | ja | 2 | ✅ |
| E4 | Profielen aanmaken bij import zodat elk recept kandidaat is | S | ja | 1 | vervalt (main: profile_later) |
| E5 | "Vergeet je niet" samenvoegen: standaardboodschappen, waarschijnlijk-op, AH-signaal, met bron | S | ja | 3 | deels (ritme + vaak; AH-signaal wacht) |

### F. Van populaire apps

| # | Item | Grootte | Offline | Prio | Status |
|---|---|---|---|---|---|
| F8 | Kooklijst "wil ik binnenkort maken", ook als input voor het voorstel | S | ja | 2 | vervalt (main: wensen met recept) |
| F9 | Week opslaan en terugzetten als sjabloon | S | ja | 3 | ✅ web + iOS |
| F10 | Kookstand: timers uit stappen, hoeveelheid in de stap | M | ja | 3 | ✅ web + iOS |
| F11 | Koken met wat er is: restjes, vriezer, nog-in-huis tegen eigen recepten | M | ja | 4 | open |

### Voorgestelde eerste sprint, volledig offline

F1, F2, F3, F4, D1, D2, E4, E1, C1, B3. Daarmee staat de datalaag, kan het gezin beoordelen, en zijn
de voorspelling en de weekkosten klaar om te vullen zodra AH terug is. F6 direct erna.

### Status 13 oktober 2026

Sprint 1 en 2 zijn eerst op een oude basis gebouwd. Tegelijk kwam op `main` een eigen gezinsfunctie
("Wie ben jij?", favorieten en Lekker? per persoon, wensen van kinderen, kinderweergave, avatars, hulppagina).
Daarom zijn alleen de unieke delen op `main` overgezet; de gezinsdelen van `main` zijn de basis.
Oude branch met alles: `backup/sprint1-2-op-oude-basis`.

**Overgezet (backend + website, offline getest):**

| Item | Gedaan | Waar |
|---|---|---|
| F1 | tabellen `ah_trips`, `ah_prices`, `ah_bonus_periods` | `models.py` |
| F2 | bestellingen en bonnen met prijs per regel, totaal en korting; terugval op de minimale query als AH de velden niet kent; kassabon-ids in één keer omgezet | `clients/ah_data.py` |
| F3 | `ah_sync.sync_trips`: alleen nieuwe ritten, max 60 per keer, backoff bij 429/5xx; `POST /api/ah/sync`, status op Instellingen | `ah_sync.py`, `api/ah_data.py` |
| F4 | prijssnapshot bij zoeken, koppelen, opslaan en bonus | `api/routes.py`, `ah_sync.record_prices` |
| F5 | dagelijkse sync van ritten en bonus in de bestaande onderhoudslus | `maintenance.daily_loop` → `ah_sync.run_daily_once` |
| A1 | bonus van volgende week: `GET /api/bonus?period=next`; bonus per periode in de tabel | `api/ah_data.py` |
| A2 | bonusrecepten voor de week waarvoor gepland wordt ("Volgende week in de bonus" zodra AH die toont) | `api/ah_data.bonus_for_week`, `kiezen.html` |
| A3 | bonus-term in beide voorstellen: Plannen (`wishes.propose`, per euro voordeel tot 15) en "Stel een gevarieerde week voor" (`nutrition.suggest_week`) | `wishes.py`, `nutrition.py` |
| E1 | uitlegbare voorstelscore met `redenen` en `uitleg` bovenop `usage.preference_score`: fans, 👍/👎, wensen, bonus, laatst gegeten, kosten | `nutrition.suggest_week`, `api/health.suggest_context` |
| B1 + B2 | pagina `/uitgaven`: staven per week, gemiddelde, per persoon per dag; per week de grootste posten en bedragen per categorie | `spend.html`, `api/insights.py` |
| B3 | kosten per recept (p.p.) en per week met bonusvoordeel; regels op Weekmenu en receptpagina | `costs.py`, `api/insights.py` |
| C1 + C2 | `replenish.predict`, `GET /api/replenish`, snooze; blok "Waarschijnlijk op" op Weekmenu; vooraan in "Vergeet je deze niet?" bij Kiezen | `replenish.py`, `weekmenu.html`, `api/ah_data.api_staples` |

**Vervallen (zit al op `main` in andere vorm):** D1 personen (→ `app/members.py`, "Wie ben jij?"), D2 beoordelen
(→ Lekker? 👍/👎 per persoon, `ratings`), D6 wensen (→ `wishes`, ook boodschappenwensen), E4 profiel bij
import (→ `maintenance.profile_later`), F8 kooklijst (→ wensen met een recept). D3 voorkeuren per persoon op
ingrediëntniveau en D4 (afleiden uit beoordelingen) blijven open, maar dan op de `ratings`-tabel van `main`.

**Daarna gebouwd (zelfde dag, ook iOS):** weekbudget (B5), "Is op" tijdens het koken (C4), basisvoorraad in
waarschijnlijk-op (C3), kooktijd per weekdag in beide voorstellen (E2), goedkoper alternatief per product (B4),
smaak per persoon met voorgestelde afkeer uit 👎 (D3/D4), en op iOS: uitgaven, waarschijnlijk-op, kosten, bonus-chip
en een bonusgroep in Zelf kiezen. De Definition of Done (app én website) is daarmee voor alles hierboven gehaald,
behalve de onderdelen die op AH wachten.

**Nog open:**

- **Wacht op AH:** F6 live-sessie (daarna A4 "koop er één bij", A6 persoonlijke bonus, B6 Premium-besparing, C5
  AH-vergeetsignalen, en E5 compleet).
- **Nu bouwbaar:** A5 vrijdagbericht over de bonus van volgende week, C6 houdbaarheid van vriezer en koelkast, D7 stemmen op
  kandidaten, D8 kids-kookavond, F9 week opslaan als sjabloon, F10 timers in de kookmodus, F11 koken met wat er is.
- **Uit de analyse:** matching rekent nog met vast 4 personen voor "per persoon"-regels; de login-proxy op poort 9928
  draait permanent.

## Bronnen

- `gwillem/appie-go`: `doc/albertheijn_api.md`, `doc/search-api.md`, `doc/graphql-schema-20260118.md`,
  `doc/feature-flags-20260118.md`, `testdata/`. https://github.com/gwillem/appie-go
- `mrserzhan/ah-mcp` (bouwt op appie-go; frequentie wordt client-side berekend in `tools/orders.go`).
  https://github.com/mrserzhan/ah-mcp
- jabbink, "Albert Heijn app API.md". https://gist.github.com/jabbink/8bfa44bdfc535d696b340c46d228fdd1
- `bartmachielsen/SupermarktConnector`. https://github.com/bartmachielsen/SupermarktConnector
- Marktonderzoek apps (Paprika, Samsung Food, AnyList, Mealime, Plan to Eat, Grocy, KitchenOwl, Bring!,
  Crouton, Pestle, eMeals, BiteBallot, AH-app, Jumbo, Picnic): samenvatting in dit plan, thema F.
- Bestaande docs: `docs/ah-integratie.md`, `docs/plan-api.md`, `docs/functionele-analyse.md`.
