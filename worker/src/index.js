// Svitlo aggregator — Cloudflare Worker
// Collects Ukrainian power-outage schedules from several sources and serves
// them in one flat format that is trivial to parse on iOS 6.
//
//   GET /regions          -> { regions: [ {id, name} ] }
//   GET /schedule/<id>    -> { id, name, updated, today, tomorrow, queues: [...] }
//
// Each queue day is a 48-char string, one char per 30 minutes starting 00:00 Kyiv:
//   '0' = power on, '1' = off, '2' = possible outage
// A day is null when no schedule is published yet.

const GH = "https://raw.githubusercontent.com/yaroslav2901/OE_OUTAGE_DATA/main/data/";
// DTEK regions (Kyiv oblast, Odesa, Dnipropetrovsk oblast), same schema — MIT, github.com/Baskerville42/outage-data-ua
const DTEK = "https://raw.githubusercontent.com/Baskerville42/outage-data-ua/main/data/";
const YASNO = "https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/";

export const REGIONS = [
  { id: "kyiv",            name: "Київ",                src: "yasno", region: 25, dso: 902 },
  { id: "dnipro",          name: "Дніпро",              src: "yasno", region: 3,  dso: 301 },
  { id: "kyiv-region",     name: "Київська",            src: "dtek", file: "kyiv-region.json" },
  { id: "odesa",           name: "Одеська",             src: "dtek", file: "odesa.json" },
  { id: "dnipro-region",   name: "Дніпропетровська",    src: "dtek", file: "dnipro.json" },
  { id: "kharkiv",         name: "Харківська",          src: "gh", file: "Kharkivoblenerho.json" },
  { id: "lviv",            name: "Львівська",           src: "gh", file: "Lvivoblenerho.json" },
  { id: "zaporizhzhia",    name: "Запорізька",          src: "gh", file: "Zaporizhzhiaoblenergo.json" },
  { id: "poltava",         name: "Полтавська",          src: "gh", file: "Poltavaoblenergo.json" },
  { id: "cherkasy",        name: "Черкаська",           src: "gh", file: "Cherkasyoblenergo.json" },
  { id: "chernihiv",       name: "Чернігівська",        src: "gh", file: "Chernihivoblenergo.json" },
  { id: "zhytomyr",        name: "Житомирська",         src: "gh", file: "Zhytomyroblenergo.json" },
  { id: "khmelnytskyi",    name: "Хмельницька",         src: "gh", file: "Khmelnytskoblenerho.json" },
  { id: "ivano-frankivsk", name: "Івано-Франківська",   src: "gh", file: "Prykarpattiaoblenerho.json" },
  { id: "rivne",           name: "Рівненська",          src: "gh", file: "Rivneoblenergo.json" },
  { id: "ternopil",        name: "Тернопільська",       src: "gh", file: "Ternopiloblenerho.json" },
  { id: "zakarpattia",     name: "Закарпатська",        src: "gh", file: "Zakarpattiaoblenerho.json" },
];

// ---------- date helpers (Kyiv time) ----------
export function kyivDate(ms) {
  // en-CA gives YYYY-MM-DD
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Kyiv" }).format(new Date(ms));
}
function addDays(dateStr, n) {
  const d = new Date(dateStr + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// ---------- GitHub / DTEK-style format ----------
// fact.data[timestamp]["GPV1.1"]["1".."24"] = yes|no|maybe|first|second|mfirst|msecond
const HALVES = {
  yes: "00", no: "11", maybe: "22",
  first: "10", second: "01",
  mfirst: "20", msecond: "02",
};

export function fromDtekFormat(raw, today) {
  const fact = (raw && raw.data && raw.data.fact) || raw.fact || raw.data || {};
  const days = fact.data && !Array.isArray(fact.data) ? fact.data : {};
  const byDate = {};
  for (const ts of Object.keys(days)) {
    const date = kyivDate(Number(ts) * 1000);
    byDate[date] = days[ts];
  }
  const tomorrow = addDays(today, 1);
  const queueIds = new Set();
  // full queue list from the weekly preset, so regions without a fresh schedule still list queues
  const names = raw.preset && raw.preset.sch_names;
  if (names && typeof names === "object") Object.keys(names).forEach((k) => queueIds.add(k));
  // queues come from any published day, so stale regions still list their queues
  for (const d of Object.values(days)) {
    if (d && typeof d === "object") Object.keys(d).forEach((k) => queueIds.add(k));
  }
  const conv = (day, gpv) => {
    if (!day || !day[gpv]) return null;
    let s = "";
    for (let h = 1; h <= 24; h++) s += HALVES[day[gpv][String(h)]] || "00";
    return s;
  };
  const queues = [...queueIds]
    .filter((k) => /^GPV\d/.test(k))
    .map((k) => ({
      id: k.replace("GPV", ""),
      today: conv(byDate[today], k),
      tomorrow: conv(byDate[tomorrow], k),
    }))
    .sort((a, b) => a.id.localeCompare(b.id, "en", { numeric: true }));
  return { updated: fact.update || raw.lastUpdated || null, queues };
}

// ---------- YASNO format ----------
// { "1.1": { today: {slots:[{start,end,type}], date, status}, tomorrow: {...}, updatedOn } }
function yasnoDay(day) {
  if (!day) return null;
  if (day.status === "NoOutages") return "0".repeat(48);
  if (!Array.isArray(day.slots) || day.slots.length === 0) {
    return day.status === "ScheduleApplies" ? "0".repeat(48) : null;
  }
  const a = new Array(48).fill("0");
  for (const s of day.slots) {
    const ch = s.type === "Definite" ? "1" : s.type === "NotPlanned" ? "0" : "2";
    const from = Math.max(0, Math.floor(s.start / 30));
    const to = Math.min(48, Math.ceil(s.end / 30));
    for (let i = from; i < to; i++) a[i] = ch;
  }
  return a.join("");
}

export function fromYasnoFormat(raw) {
  let updated = null;
  const queues = Object.keys(raw || {})
    .filter((k) => /^\d+\.\d+$/.test(k))
    .map((k) => {
      const q = raw[k];
      if (q.updatedOn && (!updated || q.updatedOn > updated)) updated = q.updatedOn;
      return { id: k, today: yasnoDay(q.today), tomorrow: yasnoDay(q.tomorrow) };
    })
    .sort((a, b) => a.id.localeCompare(b.id, "en", { numeric: true }));
  return { updated, queues };
}

// ---------- fetching ----------
async function getJSON(url) {
  const r = await fetch(url, {
    headers: { "User-Agent": "svitlo-ios6-aggregator", Accept: "application/json" },
    ...(typeof caches !== "undefined" ? { cf: { cacheTtl: 300, cacheEverything: true } } : {}),
  });
  if (!r.ok) throw new Error("upstream " + r.status);
  return r.json();
}

export async function buildSchedule(reg) {
  const today = kyivDate(Date.now());
  let res;
  if (reg.src === "gh") res = fromDtekFormat(await getJSON(GH + reg.file), today);
  else if (reg.src === "dtek") res = fromDtekFormat(await getJSON(DTEK + reg.file), today);
  else res = fromYasnoFormat(await getJSON(`${YASNO}${reg.region}/dsos/${reg.dso}/planned-outages`));
  return {
    id: reg.id,
    name: reg.name,
    updated: res.updated,
    today,
    tomorrow: addDays(today, 1),
    queues: res.queues,
  };
}

function json(body, status = 200, maxAge = 120) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${maxAge}`,
      "Access-Control-Allow-Origin": "*",
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "").replace(/\.json$/, "");

    if (path === "" || path === "/regions") {
      return json({ regions: REGIONS.map(({ id, name }) => ({ id, name })) }, 200, 3600);
    }

    const m = path.match(/^\/schedule\/([a-z-]+)$/);
    if (m) {
      const reg = REGIONS.find((r) => r.id === m[1]);
      if (!reg) return json({ error: "unknown region" }, 404);

      const cache = caches.default;
      const key = new Request(url.origin + path);
      const hit = await cache.match(key);
      if (hit) return hit;
      try {
        const resp = json(await buildSchedule(reg));
        ctx.waitUntil(cache.put(key, resp.clone()));
        return resp;
      } catch (e) {
        return json({ error: String(e.message || e) }, 502, 0);
      }
    }
    return json({ error: "not found" }, 404);
  },
};
