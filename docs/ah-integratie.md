# Albert Heijn-integratie: ingrediënten in je AH-mandje

Hoe Nomnom de ingrediënten van een recept omzet naar producten op je AH-lijst, met één klik.
Dit document is ook bedoeld als **briefing voor een coding agent**: geef het aan je agent, dan kan die
de integratie in jouw app nabouwen. Het gedeelte [Instructies voor je agent](#instructies-voor-je-agent)
staat onderaan.

> ⚠️ **Onofficiële API.** AH heeft geen publieke API. Alles hieronder gebruikt de (reverse-engineered)
> mobiele API van de Appie-app en een publieke webshop-URL. Die kunnen zonder aankondiging veranderen.
> Gebruik dit voor persoonlijke/hobbyprojecten en bouw je code zo dat een storing niet je hele app breekt.

---

## In het kort

De integratie bestaat uit twee losse stukken:

1. **Producten zoeken** (server-side): een eigen API-route haalt een anoniem token op bij `api.ah.nl`
   en zoekt per ingrediënt producten. De browser praat nooit direct met AH.
2. **Mandje vullen** (client-side): van de gekozen producten bouwen we een link naar
   `https://www.ah.nl/mijnlijst/add-multiple?p=<productnummer>:<aantal>&p=...`. Die opent in een nieuw
   tabblad; de gebruiker is daar zelf ingelogd bij AH en de producten komen op z'n lijst.

Er is dus **geen AH-login in je eigen app nodig** en je slaat geen AH-credentials op.

```
┌──────────────┐  POST /api/ah/search   ┌───────────────────┐  anoniem token + search  ┌────────────┐
│ Browser/UI   │ ─────────────────────▶ │ Next.js route     │ ───────────────────────▶ │ api.ah.nl  │
│ (modal)      │ ◀───────────────────── │ app/api/ah/search │ ◀─────────────────────── │            │
└──────┬───────┘   kandidaten per item  └───────────────────┘   producten (JSON)       └────────────┘
       │ window.open(…/mijnlijst/add-multiple?p=123:2&p=456:1)
       ▼
┌──────────────┐
│ www.ah.nl    │  gebruiker is ingelogd → producten op "Mijn lijst"
└──────────────┘
```

## Opbouw in de code

| Bestand | Rol |
| --- | --- |
| `app/api/ah/search/route.ts` | Server-route: anoniem token (gecachet), product search, kandidaten normaliseren |
| `lib/ui/ah.ts` | Pure helpers: zoekquery, hoeveelheid schatten, `add-multiple`-URL bouwen |
| `lib/ui/use-ah-cart.ts` | React-hook voor "recept → mandje": selectie, auto-zoeken, voorkeursproducten |
| `lib/ui/use-loose-cart.ts` | React-hook voor een losse boodschappenlijst (los van recepten) |
| `app/home/components/ah-cart-modal.tsx` | UI: ingrediënten aanvinken, product kiezen, knop "Open N producten bij AH" |
| `app/home/components/loose-cart-modal.tsx` | UI voor de losse lijst |
| `tests/ah.test.ts`, `tests/api/ah-search-route.test.ts`, `tests/use-ah-cart.test.tsx`, `tests/use-loose-cart.test.tsx`, `tests/components/ah-cart-modal.test.tsx` | Unit tests (Vitest), met gemockte `fetch` |


---

## 1. De AH mobiele API

### Anoniem token

```http
POST https://api.ah.nl/mobile-auth/v1/auth/token/anonymous
Content-Type: application/json; charset=UTF-8
User-Agent: Appie/8.8.2 Model/phone Android/7.0-API24
x-application: AHWEBSHOP

{ "clientId": "appie" }
```

Response (relevante velden):

```json
{ "access_token": "…", "refresh_token": "…", "expires_in": 7199 }
```

- Geen account nodig; prima voor producten zoeken.
- We cachen het token **in memory op de server** tot 60 seconden vóór het verloopt
  (`expiresAt = now + max(60, expires_in - 60) * 1000`). In serverless kan elke cold start een nieuw token
  ophalen; dat is prima.

### Boodschappenlijstje lezen (gebruikerstoken)

`GET https://api.ah.nl/mobile-services/shoppinglist/v2/items` (Bearer-gebruikerstoken) geeft `{"id", "items": [...]}`.
Per item: `quantity`, `strikedthrough` (afgestreept), `type` (`SHOPPABLE` of tekst), en
`productDetails.product.webshopId` / `title` / `salesUnitSize`. Alleen lezen.

Miso leest het lijstje vóór elke week-sync en voegt alleen toe wat er écht nog ontbreekt (`nodig - op lijstje`),
dus ook goed als je in de AH-app iets weghaalde of zelf toevoegde. Na het toevoegen leest Miso opnieuw; telt
`PATCH shoppinglist/v2/items` onverhoopt niet op maar vervangt het, dan wordt alsnog het totaal gezet.
Lukt lezen niet, dan valt Miso terug op de eigen boekhouding (`cart_pushes`).

### Producten zoeken

**Eerst: GraphQL `searchProducts` (zoals de Appie-app, sinds 2026-10).** Dit is de "slimme" zoekfunctie met
synoniemen en spellingtolerantie, vergelijkbaar met ah.nl: "parmaham" → Prosciutto di parma, "scampi" →
garnalen, "kippendijfilet" → kipdijfilet. Het oude REST-zoeken hieronder zoekt alleen letterlijk in titels en
geeft daar niets of rommel (bijv. hoofdhuidborstels voor "scampi"). Geeft altijd max. 10 producten; er is geen
size/page-argument. De website-zoek-API (`www.ah.nl/zoeken/api/...`) is voor scripts geblokkeerd (Akamai 403).

```graphql
query SearchProducts($q: String!) {
  searchProducts(input: {query: $q}) {
    products { id title brand salesUnitSize category taxonomies { name } icons
      price { now { amount } was { amount } unitInfo { description } }
      availability { isOrderable } imagePack { small { url } medium { url } } }
  }
}
```

- `id` = webshopId (werkt met `add-multiple`, lijstje en mandje). `price.was` = prijs zonder bonus.
- `category` is `"Hoofdafdeling/Subafdeling"`; gebruik het deel vóór `/` (net als `mainCategory` uit REST).
  Let op: `taxonomies` bevat ook diepere namen ("…wijnazijn"), dus niet daarop alcohol detecteren.
- Biologisch = `"ORGANIC"` in `icons`. Alcohol = hoofdafdeling begint met "Bier, wijn".
- Miso vult aan met het REST-zoeken als de app minder resultaten geeft dan gevraagd (breedte voor de
  koppelregels) en valt erop terug als GraphQL faalt.

**Reserve/aanvulling: REST (letterlijk zoeken).**

```http
GET https://api.ah.nl/mobile-services/product/search/v2?query=<zoekterm>&sortOn=RELEVANCE
Accept: application/json
Authorization: Bearer <access_token>
User-Agent: Appie/8.8.2 Model/phone Android/7.0-API24
x-application: AHWEBSHOP
```

Response bevat een `products`-array. Per product gebruiken we:

| Veld in AH-response | Ons veld | Opmerking |
| --- | --- | --- |
| `webshopId` (number) | `productNumber` | **Dit is het nummer dat `add-multiple` nodig heeft.** Fallbacks: `productNumber`, `id`, `productId` |
| `title` (fallback `description`) | `title` | |
| `salesUnitSize` (fallback `unitSize`) | `unitSize` | Bijv. `"500 g"`, `"6 stuks"`, `"2 x 250 ml"` |
| `images[0].url` | `imageUrl` | |

Als `products` ontbreekt, doorzoeken we de payload recursief (max. 6 niveaus diep) naar het eerste object
met een productnummer. Dat vangt kleine wijzigingen in de responsevorm op.

## 2. Onze eigen route: `POST /api/ah/search`

Batch-endpoint: alle ingrediënten in één request, AH-calls parallel (`Promise.all`).

**Request**

```json
{
  "items": [
    { "index": 0, "query": "kipfilet" },
    { "index": 3, "query": "rode ui" }
  ]
}
```

- `index` = positie van het ingrediënt in jouw lijst, zodat je resultaten terug kunt koppelen.
- Items zonder geldige `index` (number) of lege `query` worden genegeerd; blijft er niets over → `400 { "error": "Invalid payload" }`.

**Response `200`**

```json
{
  "results": [
    {
      "index": 0,
      "query": "kipfilet",
      "productNumber": "123456",
      "title": "AH Kipfilet",
      "candidates": [
        { "productNumber": "123456", "title": "AH Kipfilet", "unitSize": "500 g", "imageUrl": "https://…" },
        { "productNumber": "234567", "title": "AH Biologisch kipfilet", "unitSize": "300 g" }
      ]
    },
    { "index": 3, "query": "rode ui", "error": "Producten ophalen mislukt" }
  ]
}
```

- `productNumber`/`title` = de eerste (meest relevante) kandidaat; de gebruiker kan een andere kiezen.
- Fouten zijn **per item**: één mislukte zoekopdracht breekt de rest niet.
- Geen resultaat → `{ "error": "Geen product gevonden" }` voor dat item.
- De route valt onder de Supabase-middleware (`/api/:path*`), dus alleen ingelogde gebruikers kunnen hem aanroepen.
  Doe dat ook: anders is je route een open proxy naar AH.

## 3. Mandje vullen: `add-multiple`-URL

```
https://www.ah.nl/mijnlijst/add-multiple?p=123456:2&p=234567:1
```

- Eén `p`-parameter per product, formaat `<webshopId>:<aantal>`.
- Aantal wordt afgerond naar een geheel getal ≥ 1.
- Openen met `window.open(url, "_blank", "noopener,noreferrer")`. Is de gebruiker niet ingelogd bij AH,
  dan vraagt ah.nl daar zelf om.

```ts
// lib/ui/ah.ts
export function buildAhAddMultipleUrl(items: { productNumber: string; quantity: number }[]) {
  const params = new URLSearchParams();
  items.forEach((item) => params.append('p', `${item.productNumber}:${normalizeAhQuantity(item.quantity)}`));
  return `https://www.ah.nl/mijnlijst/add-multiple?${params.toString()}`;
}
```

## 4. Slimme details (optioneel, maar maken het verschil)

**Hoeveel verpakkingen?** — `guessAhCartQuantity(ingredient, unitSize)` in `lib/ui/ah.ts`:

| Ingrediënt | Regel |
| --- | --- |
| Gram/kg/ml/l en verpakking in dezelfde eenheid | `ceil(benodigd / verpakking)`, bijv. 750 g bij 500 g-pak → 2 |
| Verpakking in stuks (`"6 stuks"`) | `ceil(aantal / stuks per pak)` |
| Tenen knoflook | `ceil(tenen / 8)` (1 bol ≈ 8 tenen) |
| Bosui / eenheid `bos` | `ceil(aantal / 6)` |
| Theelepel/eetlepel, `cm` | altijd 1 |
| Onbekende eenheid | afgerond aantal, maar > 10 wordt 1 (waarschijnlijk geen stuks) |

Het aantal personen wordt eerst geschaald (`scaleQuantityForServings`) als de gebruiker de porties aanpast.

**Basisvoorraad standaard uit.** Ingrediënten als zout, peper, olie, olijfolie, knoflook, water, azijn, suiker,
bloem en bakpapier staan standaard uitgevinkt (`isPantryStaple`), want die heeft men meestal al.

**Voorkeursproducten onthouden.** Kiest de gebruiker een ander product voor "kipfilet", dan bewaren we dat in
`localStorage` (`nomnom.preferred-ah-products`, key = ingrediëntnaam in lowercase). Bij een volgende zoekopdracht
wordt die keuze automatisch geselecteerd als hij tussen de kandidaten zit.

**Handmatig opnieuw zoeken.** Per ingrediënt kan de gebruiker een eigen zoekterm invullen; dat is dezelfde route
met één item.

---

## Relevante repo's en bronnen

- **jabbink – "Albert Heijn app API.md"** (gist): documentatie van de mobiele API, incl. anoniem token, login via OAuth,
  refresh en product search. <https://gist.github.com/jabbink/8bfa44bdfc535d696b340c46d228fdd1>
- **bartmachielsen/SupermarktConnector** (Python): producten ophalen bij AH en Jumbo via de mobiele API.
  <https://github.com/bartmachielsen/SupermarktConnector>
- **mrserzhan/ah-mcp** (Go): MCP-server voor de AH API (zoeken, bonus, winkelwagen, bestellingen, bonnetjes) met
  OAuth-login. Handig als je verder wilt dan "op de lijst zetten". <https://github.com/mrserzhan/ah-mcp>

---

## Instructies voor je agent

> Kopieer dit blok naar je agent, samen met de rest van dit document.

Implementeer een Albert Heijn-integratie volgens dit document. Pas het aan aan de stack van deze repo
(het voorbeeld is Next.js App Router + TypeScript, maar het patroon werkt met elke backend).

1. **Server-route `POST /api/ah/search`** (of het equivalent in deze stack)
   - Haal een anoniem token op via `POST https://api.ah.nl/mobile-auth/v1/auth/token/anonymous`
     met body `{"clientId":"appie"}` en de headers `User-Agent: Appie/8.8.2 Model/phone Android/7.0-API24`
     en `x-application: AHWEBSHOP`. Cache het in memory tot 60 s vóór `expires_in`.
   - Zoek per item via `GET https://api.ah.nl/mobile-services/product/search/v2?query=…&sortOn=RELEVANCE`
     met `Authorization: Bearer <token>` en dezelfde headers.
   - Map `products[]` naar `{ productNumber (webshopId), title, unitSize (salesUnitSize), imageUrl (images[0].url) }`.
   - Valideer de input (`items: {index:number, query:string}[]`, lege queries eruit, anders 400).
   - Voer zoekopdrachten parallel uit en vang fouten **per item** af. Geef nooit ruwe AH-fouten door aan de client.
   - Zet de route achter de bestaande authenticatie; het is server-only code (geen calls vanuit de browser naar api.ah.nl).
2. **Helper `buildAhAddMultipleUrl(items)`**: `https://www.ah.nl/mijnlijst/add-multiple?p=<id>:<qty>&p=…`,
   aantal afgerond en ≥ 1.
3. **UI**: lijst van ingrediënten met checkbox (basisvoorraad standaard uit), per ingrediënt de gevonden
   kandidaat met mogelijkheid om een andere te kiezen of opnieuw te zoeken, en een knop die de URL opent met
   `window.open(url, "_blank", "noopener,noreferrer")`. Toegankelijk: labels, focus states, toetsenbord.
4. **Optioneel**: hoeveelheid schatten op basis van `unitSize` (tabel in §4) en gekozen producten per
   ingrediëntnaam onthouden in `localStorage` (try/catch rond lezen/schrijven).
5. **Tests**: unit tests voor de URL-builder, hoeveelheidslogica, input-validatie van de route en de
   token-cache, met gemockte `fetch`. Geen echte calls naar AH in tests.

Let op: dit is een onofficiële API. Ga er niet van uit dat de responsevorm stabiel is (gebruik fallbacks
voor veldnamen) en zorg dat de rest van de app blijft werken als AH niet antwoordt.
