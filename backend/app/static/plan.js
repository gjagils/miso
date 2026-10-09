/* Miso: herbruikbare "Inplannen"-dialoog (recept, restjes, uit de vriezer / hebben we al).
 *
 * MisoPlan.open({
 *   recipe:  {id, name, image_url, servings}   vast recept (geen zoeken)
 *   tabs:    true                               tabs "Recept" en "Uit de vriezer / hebben we al" met zoeken
 *   tab:     "recipe" | "stock"
 *   freezerItem: {id, name, portions}          voorgeselecteerd vriezer-item (stock-tab)
 *   date:    "YYYY-MM-DD"                       voorgeselecteerde dag
 *   start:   "YYYY-MM-DD"                       eerste dag van de 7 dagchips (default: vandaag)
 *   mode:    "plan" (opslaan via POST /api/plan/entries) | "move" (PATCH entry) | "pick" (alleen teruggeven)
 *   entry:   planregel (mode "move")
 *   persons, cookDouble: startwaarden (mode "pick")
 *   onDone:  callback(result)
 * })
 * Alle gebruikersinvoer gaat via textContent/esc; nooit ongefilterde HTML.
 */
(() => {
const DAYS = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"];
const SHORT = ["ma", "di", "wo", "do", "vr", "za", "zo"];
const MONTHS = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"];
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c]));
const iso = d => d.toLocaleDateString("sv-SE");
const parseIso = s => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
const addDays = (s, n) => { const d = parseIso(s); d.setDate(d.getDate() + n); return iso(d); };
const wd = s => (parseIso(s).getDay() + 6) % 7;
const dayLabel = s => { const d = parseIso(s); return `${DAYS[wd(s)]} ${d.getDate()} ${MONTHS[d.getMonth()]}`; };
const today = () => iso(new Date());

async function api(method, url, body) {
    try {
        const r = await fetch(url, {method, headers: body ? {"Content-Type": "application/json"} : {},
                                    body: body ? JSON.stringify(body) : undefined});
        let data = {};
        try { data = await r.json(); } catch (e) { data = {}; }
        if (!r.ok) {
            const detail = Array.isArray(data.detail) ? "Controleer de invoer." : data.detail;
            return {ok: false, error: data.error || detail || `Fout ${r.status}`};
        }
        return data.ok === undefined ? {...data, ok: true} : data;
    } catch (e) { return {ok: false, error: "Geen verbinding met Miso."}; }
}

let settings = null, ownRecipes = null;
async function household() {
    if (!settings) settings = await api("GET", "/api/plan/settings");
    return (settings && settings.household_size) || 4;
}
async function loadOwn() {
    if (!ownRecipes) { const r = await api("GET", "/api/recipes"); ownRecipes = r.recipes || []; }
    return ownRecipes;
}

function summary(resp) {
    const e = (resp.entries || [])[0];
    if (!e) return "Ingepland.";
    let t = `${e.title} staat op ${dayLabel(e.date)}`;
    if (e.kind !== "stock") t += ` (voor ${e.persons})`;
    const rest = (resp.entries || []).find(x => x.kind === "leftover" && x.source_entry_id === e.entry_id);
    if (rest) t += `, de rest op ${dayLabel(rest.date)}`;
    if (resp.freezer_item && e.cook_double === "freezer") t += `, ${resp.freezer_item.portions} porties naar de vriezer`;
    return t + ".";
}

// ── DOM ───────────────────────────────────────────────────────────────
let dlg, st;
function build() {
    dlg = document.createElement("dialog");
    dlg.className = "mp";
    dlg.setAttribute("aria-labelledby", "mp-title");
    dlg.innerHTML = `
    <form method="dialog" class="mp-form" novalidate>
      <div class="mp-head">
        <h2 id="mp-title"></h2>
        <button type="button" class="btn-close" data-close aria-label="Sluiten">✕</button>
      </div>
      <div class="mp-tabs" role="tablist" hidden>
        <button type="button" role="tab" data-tab="recipe">Recept</button>
        <button type="button" role="tab" data-tab="stock">Uit de vriezer / hebben we al</button>
      </div>
      <div class="mp-panel" data-panel="recipe">
        <div class="mp-chosen" hidden></div>
        <div class="mp-search">
          <input type="search" class="form-input" placeholder="Zoek in je recepten en Allerhande" aria-label="Zoek een recept" autocomplete="off" enterkeyhint="search">
          <ul class="mp-results" aria-live="polite"></ul>
          <p class="muted mp-ah-status"></p>
        </div>
      </div>
      <div class="mp-panel" data-panel="stock" hidden>
        <div class="mp-freezer" hidden>
          <p class="mp-label">In de vriezer</p>
          <div class="mp-freezer-list"></div>
        </div>
        <label class="mp-label" for="mp-text">Wat eten jullie?</label>
        <input id="mp-text" class="form-input" maxlength="300" placeholder="Bijv. pastasaus uit de vriezer, pannenkoeken">
        <label class="mp-label" for="mp-extras">Moet er nog iets bij? <span class="muted">(één per regel)</span></label>
        <textarea id="mp-extras" rows="3" placeholder="Pasta&#10;Parmezaan"></textarea>
      </div>
      <fieldset class="mp-days">
        <legend class="mp-label">Welke dag?</legend>
        <div class="mp-daynav">
          <button type="button" class="mp-nav" data-shift="-7" aria-label="Vorige 7 dagen">‹</button>
          <div class="mp-chips"></div>
          <button type="button" class="mp-nav" data-shift="7" aria-label="Volgende 7 dagen">›</button>
        </div>
        <p class="muted mp-dayinfo" aria-live="polite"></p>
      </fieldset>
      <div class="mp-persons">
        <span class="mp-label" id="mp-persons-label">Voor hoeveel personen?</span>
        <div class="mp-stepper" role="group" aria-labelledby="mp-persons-label">
          <button type="button" data-step="-1" aria-label="Eén persoon minder">−</button>
          <output aria-live="polite"></output>
          <button type="button" data-step="1" aria-label="Eén persoon meer">+</button>
        </div>
      </div>
      <div class="mp-double">
        <label class="mp-switch"><input type="checkbox" id="mp-double"> <span>Kook dubbel</span></label>
        <div class="mp-seg" role="radiogroup" aria-label="Wat doe je met de rest?" hidden>
          <label><input type="radio" name="mp-rest" value="tomorrow" checked><span>morgen opeten</span></label>
          <label><input type="radio" name="mp-rest" value="freezer"><span>naar de vriezer</span></label>
        </div>
      </div>
      <p class="mp-error" role="alert" hidden></p>
      <div class="mp-foot">
        <button type="submit" class="btn btn-primary mp-submit">Inplannen</button>
      </div>
    </form>`;
    document.body.appendChild(dlg);
    const q = sel => dlg.querySelector(sel);
    dlg.addEventListener("click", e => { if (e.target === dlg) dlg.close(); });  // tik buiten de sheet
    q("[data-close]").onclick = () => dlg.close();
    dlg.querySelectorAll("[data-tab]").forEach(b => b.onclick = () => setTab(b.dataset.tab));
    dlg.querySelectorAll("[data-shift]").forEach(b => b.onclick = () => { st.start = addDays(st.start, Number(b.dataset.shift)); renderDays(); });
    dlg.querySelectorAll("[data-step]").forEach(b => b.onclick = () => {
        st.persons = Math.max(1, Math.min(20, st.persons + Number(b.dataset.step))); renderPersons();
    });
    q("#mp-double").onchange = () => { q(".mp-seg").hidden = !q("#mp-double").checked; };
    let timer = null;
    q(".mp-search input").addEventListener("input", () => { clearTimeout(timer); renderOwn(); timer = setTimeout(searchAh, 350); });
    q(".mp-search input").addEventListener("keydown", e => { if (e.key === "Enter") { e.preventDefault(); clearTimeout(timer); searchAh(); } });
    q(".mp-form").addEventListener("submit", e => { e.preventDefault(); submit(); });
}
const $q = sel => dlg.querySelector(sel);

function setTab(tab) {
    st.tab = tab;
    dlg.querySelectorAll("[data-tab]").forEach(b => b.setAttribute("aria-selected", b.dataset.tab === tab ? "true" : "false"));
    dlg.querySelectorAll("[data-panel]").forEach(p => { p.hidden = p.dataset.panel !== tab; });
    $q(".mp-double").hidden = tab !== "recipe" || st.mode !== "plan" && st.mode !== "pick";
    $q(".mp-persons").hidden = tab === "stock";
    if (tab === "stock") loadFreezer();
}

function renderPersons() { $q(".mp-stepper output").textContent = st.persons; }

async function renderDays() {
    const wrap = $q(".mp-chips");
    const dates = [...Array(7)].map((_, i) => addDays(st.start, i));
    const t = today();
    const my = ++st.daySeq;
    const r = await api("GET", `/api/plan/entries?start=${st.start}&days=7`);
    if (my !== st.daySeq) return;
    const busy = {};
    (r.entries || []).forEach(e => {
        if (st.entry && e.entry_id === st.entry.entry_id) return;
        (busy[e.date] = busy[e.date] || []).push(e.title);
    });
    wrap.innerHTML = "";
    dates.forEach(d => {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "mp-chip" + (busy[d] ? " busy" : "") + (d === t ? " is-today" : "");
        b.disabled = d < t;
        b.setAttribute("aria-pressed", d === st.date ? "true" : "false");
        b.setAttribute("aria-label", `${dayLabel(d)}${busy[d] ? ", al gepland: " + busy[d].join(", ") : ""}`);
        b.innerHTML = `<span class="mp-wd">${SHORT[wd(d)]}</span><span class="mp-dn">${parseIso(d).getDate()}</span><span class="mp-dot" aria-hidden="true"></span>`;
        b.onclick = () => { st.date = d; renderDays(); };
        wrap.appendChild(b);
    });
    const info = $q(".mp-dayinfo");
    info.textContent = st.date ? (busy[st.date] ? `${dayLabel(st.date)}: er staat al ${busy[st.date].join(", ")}` : dayLabel(st.date)) : "Kies een dag.";
}

function renderChosen() {
    const box = $q(".mp-chosen");
    const c = st.recipe;
    box.hidden = !c;
    $q(".mp-search").hidden = !!c && !st.tabs;
    if (!c) return;
    box.innerHTML = `${c.image_url ? `<img src="${esc(c.image_url)}" alt="" referrerpolicy="no-referrer">` : `<span class="mp-ph"></span>`}
        <span class="mp-chosen-name">${esc(c.name)}${c.servings ? `<span class="muted">recept voor ${esc(c.servings)}</span>` : ""}</span>
        ${st.tabs ? `<button type="button" class="kz-linkbtn" data-unpick>Ander recept</button>` : ""}`;
    const un = box.querySelector("[data-unpick]");
    if (un) un.onclick = () => { st.recipe = null; renderChosen(); $q(".mp-search input").focus(); };
    if (st.tabs) $q(".mp-search").hidden = true;
}

function resultRow(item) {
    const li = document.createElement("li");
    const b = document.createElement("button");
    b.type = "button"; b.className = "mp-result";
    b.innerHTML = `${item.image_url ? `<img src="${esc(item.image_url)}" alt="" loading="lazy" referrerpolicy="no-referrer">` : `<span class="mp-ph"></span>`}
        <span><span class="mp-rname">${esc(item.name)}</span><span class="muted">${esc(item.meta || "")}</span></span>`;
    b.onclick = () => { st.recipe = item; renderChosen(); };
    li.appendChild(b);
    return li;
}

async function renderOwn() {
    const qv = $q(".mp-search input").value.trim().toLowerCase();
    const own = await loadOwn();
    const terms = qv.split(/\s+/).filter(Boolean);
    const hits = own.filter(r => terms.every(t => r.name.toLowerCase().includes(t))).slice(0, qv ? 12 : 6);
    const ul = $q(".mp-results");
    ul.querySelectorAll("li.own, li.mp-hint").forEach(li => li.remove());
    if (!hits.length && qv) {
        const li = document.createElement("li"); li.className = "mp-hint muted"; li.textContent = `Geen eigen recept met "${qv}".`;
        ul.prepend(li);
    }
    hits.reverse().forEach(r => {
        const li = resultRow({kind: "own", id: r.id, name: r.name, image_url: r.image_url, servings: r.servings,
                              meta: ["jouw recept", r.servings].filter(Boolean).join(" · ")});
        li.className = "own"; ul.prepend(li);
    });
}

async function searchAh() {
    const qv = $q(".mp-search input").value.trim();
    const ul = $q(".mp-results"), status = $q(".mp-ah-status");
    ul.querySelectorAll("li.ah").forEach(li => li.remove());
    if (qv.length < 2) { status.textContent = ""; return; }
    const my = ++st.ahSeq;
    status.textContent = "Miso snuffelt in Allerhande...";
    const r = await api("GET", `/api/allerhande/search?q=${encodeURIComponent(qv)}`);
    if (my !== st.ahSeq) return;
    if (!r.ok) { status.textContent = r.error || "Zoeken bij AH mislukt."; return; }
    const own = await loadOwn();
    const results = (r.results || []).filter(x => !own.some(o => o.name === x.title)).slice(0, 8);
    status.textContent = results.length ? "" : `Niets extra gevonden in Allerhande voor "${qv}".`;
    results.forEach(x => {
        const li = resultRow({kind: "ah", id: x.id, name: x.title, image_url: x.image_url, servings: x.servings,
                              meta: ["Allerhande", x.time, x.servings].filter(Boolean).join(" · ")});
        li.className = "ah"; ul.appendChild(li);
    });
}

async function loadFreezer() {
    const r = await api("GET", "/api/freezer");
    const items = r.items || [];
    const box = $q(".mp-freezer"), list = $q(".mp-freezer-list");
    box.hidden = !items.length;
    list.innerHTML = "";
    items.forEach(it => {
        const b = document.createElement("button");
        b.type = "button"; b.className = "mp-fz";
        b.setAttribute("aria-pressed", st.freezer && st.freezer.id === it.id ? "true" : "false");
        b.innerHTML = `<span>${esc(it.name)}</span><span class="muted">${it.portions} ${it.portions === 1 ? "portie" : "porties"}</span>`;
        b.onclick = () => {
            const on = !(st.freezer && st.freezer.id === it.id);
            st.freezer = on ? it : null;
            const txt = $q("#mp-text");
            if (on && (!txt.value || txt.dataset.auto)) { txt.value = `${it.name} uit de vriezer`; txt.dataset.auto = "1"; }
            if (!on && txt.dataset.auto) { txt.value = ""; delete txt.dataset.auto; }
            loadFreezer();
        };
        list.appendChild(b);
    });
}

function showError(msg) { const p = $q(".mp-error"); p.textContent = msg; p.hidden = !msg; }

async function submit() {
    showError("");
    if (!st.date) return showError("Kies een dag.");
    const btn = $q(".mp-submit");
    const double = st.tab === "recipe" && $q("#mp-double").checked ? $q("input[name=mp-rest]:checked").value : null;
    if (st.mode === "pick") {
        dlg.close();
        st.onDone && st.onDone({date: st.date, persons: st.persons, cook_double: double});
        return;
    }
    btn.disabled = true; btn.textContent = "Bezig...";
    let r;
    if (st.mode === "move") {
        const body = {date: st.date};
        if (st.entry.kind !== "stock" && st.persons !== st.entry.persons) body.persons = st.persons === st.household ? null : st.persons;
        r = await api("PATCH", `/api/plan/entries/${st.entry.entry_id}`, body);
    } else if (st.tab === "stock") {
        const text = $q("#mp-text").value.trim();
        if (!text && !st.freezer) { btn.disabled = false; btn.textContent = st.submitLabel; return showError("Vul in wat jullie eten."); }
        r = await api("POST", "/api/plan/entries", {date: st.date, kind: "stock", text,
            extras: $q("#mp-extras").value.split("\n").map(s => s.trim()).filter(Boolean),
            freezer_item_id: st.freezer ? st.freezer.id : null});
    } else {
        let rec = st.recipe;
        if (!rec) { btn.disabled = false; btn.textContent = st.submitLabel; return showError("Kies eerst een recept."); }
        if (rec.kind === "ah") {
            btn.textContent = "Recept ophalen...";
            const fd = new FormData(); fd.append("recipe_id", rec.id);
            let add;
            try { add = await (await fetch("/api/allerhande/add", {method: "POST", body: fd})).json(); } catch (e) { add = {ok: false}; }
            if (!add.ok) { btn.disabled = false; btn.textContent = st.submitLabel; return showError(add.error || "Recept ophalen bij AH mislukt."); }
            rec = {...rec, kind: "own", id: add.id};
            ownRecipes = null;
        }
        r = await api("POST", "/api/plan/entries", {date: st.date, kind: "recipe", recipe_id: rec.id,
            persons: st.persons === st.household ? null : st.persons, cook_double: double});
    }
    btn.disabled = false; btn.textContent = st.submitLabel;
    if (!r.ok) return showError(r.error || "Opslaan mislukt.");
    dlg.close();
    st.onDone && st.onDone(r);
}

async function open(opts = {}) {
    if (!dlg) build();
    const hh = await household();
    const mode = opts.mode || "plan";
    st = {
        mode, tabs: !!opts.tabs, recipe: opts.recipe ? {kind: "own", ...opts.recipe} : null, entry: opts.entry || null,
        freezer: opts.freezerItem || null, household: hh, onDone: opts.onDone, daySeq: 0, ahSeq: 0,
        date: opts.date || (opts.entry && opts.entry.date) || "",
        persons: opts.persons || (opts.entry && opts.entry.persons) || hh,
        tab: opts.tab || (opts.freezerItem ? "stock" : "recipe"),
    };
    const t = today();
    st.start = opts.start || t;
    if (st.date && (st.date < st.start || st.date > addDays(st.start, 6))) st.start = st.date;
    if (!st.date && mode === "plan") st.date = st.start >= t ? st.start : t;
    st.submitLabel = mode === "move" ? "Opslaan" : mode === "pick" ? "Klaar" : "Inplannen";
    $q(".mp-submit").textContent = st.submitLabel;
    const title = mode === "move" ? `${st.entry.title} verplaatsen`
        : st.recipe && !st.tabs ? st.recipe.name : st.date ? `Wat eten we ${dayLabel(st.date).split(" ")[0]}?` : "Inplannen";
    $q("#mp-title").textContent = title;
    $q(".mp-tabs").hidden = !st.tabs;
    $q(".mp-search input").value = "";
    $q(".mp-results").innerHTML = ""; $q(".mp-ah-status").textContent = "";
    $q("#mp-text").value = st.freezer ? `${st.freezer.name} uit de vriezer` : "";
    if (st.freezer) $q("#mp-text").dataset.auto = "1"; else delete $q("#mp-text").dataset.auto;
    $q("#mp-extras").value = "";
    $q("#mp-double").checked = !!opts.cookDouble;
    $q(".mp-seg").hidden = !opts.cookDouble;
    if (opts.cookDouble) dlg.querySelector(`input[name=mp-rest][value=${opts.cookDouble}]`).checked = true;
    showError("");
    const isMove = mode === "move";
    dlg.querySelectorAll("[data-panel]").forEach(p => { p.hidden = isMove; });
    setTab(isMove ? (st.entry.kind === "stock" ? "stock" : "recipe") : st.tab);
    if (isMove) {
        dlg.querySelectorAll("[data-panel]").forEach(p => { p.hidden = true; });
        $q(".mp-double").hidden = true;
        $q(".mp-persons").hidden = st.entry.kind === "stock";
    }
    renderChosen(); renderPersons(); renderDays();
    if (st.tabs && !st.recipe) renderOwn();
    dlg.showModal();
}

window.MisoPlan = {open, esc, dayLabel, summary, api, addDays};
})();
