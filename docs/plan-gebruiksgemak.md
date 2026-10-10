# Plan: Miso makkelijker maken (10 oktober 2026)

## Uitgangspunt

De app heeft twee vragen, niet vijf tabbladen:

1. **"Ik ga vandaag koken. Wat moet ik doen?"**
2. **"Ik ga boodschappen bestellen. Wat willen we de komende dagen eten?"**

Nu zit dat verspreid over Vandaag, Wat eten we?, Weekmenu en Recepten. "Wat eten we?" is de flow om recepten te
kiezen, in te plannen en de boodschappen te doen. "Recepten" is je bibliotheek: bladeren, importeren, bewerken en
koken. Voor de gebruiker voelt dat als twee keer hetzelfde.

## Nieuwe indeling

| Tab | Vraag | Wat je ziet |
|---|---|---|
| **Vandaag** | Ik ga koken | Gerecht van vandaag groot, met de knop "Start met koken" (kookmodus). Morgen en overmorgen klein eronder. Niets gepland? Dan drie snelle voorstellen: een favoriet, "iets uit de vriezer" en "iets snels". |
| **Plannen** | Ik ga bestellen | Wensen per dag, Miso stelt recepten voor, jij wisselt of bevestigt, en één knop zet alles op je AH-lijstje. Dit vervangt "Wat eten we?" en "Weekmenu". |
| **Recepten** | Bibliotheek | Zoeken, Favorieten, Al lang niet gegeten, importeren en bewerken. |
| **Meer** | Instellingen | Gezin, AH, Ontbrekend, weergave. |

## 1. Plannen met wensen per dag (kern)

Je zegt per dag wat je zin hebt, kort en in je eigen woorden:

| Dag | Wens | Miso begrijpt | Wat er gebeurt |
|---|---|---|---|
| Ma | "iets met rijst" | basis = rijst | 3 voorstellen met rijst (profielen kennen de basis al) |
| Di | "iets met wraps" | basis = wraps | 3 voorstellen met wraps of tortilla's |
| Wo | "uit de vriezer" | voorraad | Dag zonder boodschappen ("we eten iets uit de vriezer"). Vriezerbeheer komt later. |
| Do | "lasagne" | gerecht | Je lasagne-recepten; heb je er geen, dan uit Allerhande |
| Vr | "geen idee" | vrij | Beste keuze voor variatie, gezondheid en favorieten (bestaande `suggest_week`) |
| Za | "uit eten" / "niks" | geen | Dag overslaan |

**Invoer** op twee manieren:
- Per dag een chip-kiezer: Rijst · Pasta · Aardappel · Wraps · Vis · Vega · Uit de vriezer · Geen idee · Overslaan.
- Of één zin typen: "maandag rijst, dinsdag wraps, woensdag vriezer, donderdag lasagne, vrijdag geen idee".
  Claude zet die zin om naar de wensen per dag (vaste JSON-vorm, zoals de gezondheidsprofielen al doen).

**Voorstel per dag:** het beste recept plus twee alternatieven om op te tikken. Wisselen kan met één tik. Het
voorstel houdt rekening met:
- de wens (basis, gerecht, keuken);
- variatie over de week (niet twee keer hetzelfde eiwit of dezelfde keuken);
- favorieten en hoe vaak je iets kookt (zie 3);
- bonus bij AH (bestaat al);
- "recent gegeten" (niet hetzelfde als vorige week).

**Bevestigen:** de knop "Zet op mijn AH-lijstje" plant alles in en vult het lijstje. De sync leest het echte lijstje
eerst, dus er komt niets dubbel op.

**Technisch:** grotendeels hergebruik.
- `nutrition.suggest_week` krijgt filters per dag.
- De profielen hebben al `basis`, `eiwit` en `keuken`.
- Nieuw zijn alleen `POST /api/plan/wishes` (zin naar wensen), `POST /api/plan/propose` (wensen naar voorstellen
  per dag) en het scherm.

## 2. Vandaag: koken

- Groot het gerecht van vandaag, met wat je nog moet doen ("vlees uit de vriezer halen") als het recept dat zegt.
- "Start met koken" opent de kookmodus.
- Na het koken één vraag: **"Lekker?"** met 👍, 👎 of "nog eens maken". Dit voedt het leren (3).
- Niets gepland? Dan drie voorstellen, en "Toch iets anders" opent Plannen voor alleen vandaag.

## 3. Leren van gebruik en favorieten

**Signalen** die Miso al heeft of makkelijk vastlegt:
- **Ingepland:** het aantal keren per recept (planregels bestaan al).
- **Gekookt:** de kookmodus is geopend of afgerond.
- **Oordeel na het koken:** 👍 of 👎.
- **Hartje:** je zet een recept zelf bij je favorieten.
- **Afgewezen voorstel:** je wisselt een voorstel weg. Dat is een zwak negatief signaal.

**Score per recept:**

```
favoriet +30 · 👍 +10 per keer · 👎 −25 · vaak gepland +2 per keer (max +10)
recent gegeten (< 14 dagen) −20 · vaak weggewisseld −5 per keer (max −15)
```

De voorstellen sorteren hierop, en Recepten krijgt de filters "Favorieten" en "Al lang niet gegeten".

**Technisch:**
- Nieuwe tabel `recipe_stats` (recipe_id, favoriet, gekookt, duim_op, duim_neer, weggewisseld, laatst_gekookt).
- Nieuwe endpoints: favoriet zetten, oordeel geven en "gekookt" melden vanuit de kookmodus.
- Geen machine learning nodig: een eerlijke optelsom is hier beter uit te leggen en te sturen.

## 4. Later

- Vriezerbeheer uitbreiden (nu: "uit de vriezer" als dag zonder boodschappen).
- Wensen onthouden: "maandag is meestal rijst" als standaard.
- Spraak: de zin uit stap 1 inspreken (iOS dicteren werkt al in het tekstveld).

## Volgorde en omvang

| Stap | Wat | Omvang |
|---|---|---|
| 1 | Favorieten en gebruik bijhouden (hartje, gekookt, 👍/👎) op web en iOS | klein |
| 2 | Plannen met wensen per dag (chips + voorstel + wisselen + één knop), web | middel |
| 3 | Hetzelfde in iOS, plus de zin-invoer met Claude | middel |
| 4 | Tabs herindelen: Vandaag · Plannen · Recepten · Meer; "Wat eten we?" en "Weekmenu" gaan op in Plannen | middel |
| 5 | Vandaag als kook-startscherm met "Lekker?" na het koken | klein |

Stap 1 eerst: dan verzamelt Miso al gebruiksgegevens terwijl stap 2 en 3 gebouwd worden.
