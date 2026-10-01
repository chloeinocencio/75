/* 75 — challenge tracker.
 *
 * State lives in localStorage; photographs live in IndexedDB as blobs (too large for
 * localStorage's quota). Everything stays on the device: there is no server.
 */
"use strict";

/* ------------------------------------------------------------------ tiers */

const OZ_PER_L = 33.814;
const LB_PER_KG = 2.20462;

const TIERS = {
  soft: {
    name: "75 Soft",
    tagline: "Forgiving. Miss a day and you carry on from where you left off.",
    rules: ["45 min workout", "1 rest day a week", "3 L water", "10 pages"],
    photoCadence: "milestone",
    restDay: true,
    failure: { kind: "forgiving" },
    tasks: [
      { id: "workout", type: "check", icon: "workout", title: "45-Minute Workout" },
      { id: "diet", type: "check", icon: "diet", title: "Eat Well Today" },
      { id: "water", type: "count", icon: "water", title: "Water", goal: { litres: 3 }, step: 0.25, unit: "L", dec: 1 },
      { id: "reading", type: "count", icon: "reading", title: "Reading", goal: { fixed: 10 }, step: 1, unit: " pages", dec: 0 }
    ]
  },
  medium: {
    name: "75 Medium",
    tagline: "Structure with an allowance — finish by completing 68 of the 75 days.",
    rules: ["45 min workout", "90/10 diet", "No alcohol", "10 min reading", "5 min meditation"],
    photoCadence: "milestone",
    restDay: false,
    failure: { kind: "budget", allowed: 7 },
    tasks: [
      { id: "workout", type: "check", icon: "workout", title: "45-Minute Workout" },
      { id: "diet", type: "check", icon: "diet", title: "Diet (90/10)" },
      { id: "water", type: "count", icon: "water", title: "Water", goal: { halfBodyWeightOz: true }, step: 0.25, unit: "L", dec: 1 },
      { id: "alcohol", type: "check", icon: "alcohol", title: "No Alcohol" },
      { id: "reading", type: "count", icon: "reading", title: "Reading", goal: { fixed: 10 }, step: 1, unit: " min", dec: 0 },
      { id: "meditation", type: "count", icon: "meditation", title: "Meditation", goal: { fixed: 5 }, step: 1, unit: " min", dec: 0 }
    ]
  },
  hard: {
    name: "75 Hard",
    tagline: "No grace days. Miss anything and the challenge restarts at Day 1.",
    rules: ["2 × 45 min, 1 outdoors", "Strict diet", "No alcohol", "1 gallon water", "Daily photo"],
    photoCadence: "daily",
    restDay: false,
    failure: { kind: "restart" },
    tasks: [
      { id: "workout", type: "check", icon: "workout", title: "2 × 45-Min Workouts", note: "One must be outdoors" },
      { id: "diet", type: "check", icon: "diet", title: "Diet — No Cheats" },
      { id: "water", type: "count", icon: "water", title: "Water", goal: { litres: 3.785 }, step: 0.25, unit: "L", dec: 1, note: "One gallon" },
      { id: "alcohol", type: "check", icon: "alcohol", title: "No Alcohol" },
      { id: "reading", type: "count", icon: "reading", title: "Reading", goal: { fixed: 10 }, step: 1, unit: " pages", dec: 0, note: "Non-fiction" },
      { id: "photo", type: "check", icon: "photo", title: "Progress Photo" }
    ]
  }
};

const POSES = ["Front", "Side", "Back"];

const ICON = {
  workout: '<path d="M4 12h2l2-5 3 10 2.5-7 1.5 4h5"/>',
  diet: '<path d="M5 3v8a2 2 0 0 0 4 0V3"/><path d="M7 11v10"/><path d="M15 21V3c2.5 1 4 3.5 4 6.5S17.5 15 15 15"/>',
  water: '<path d="M12 3s5.5 6 5.5 10a5.5 5.5 0 0 1-11 0C6.5 9 12 3 12 3z"/>',
  reading: '<path d="M3 5.5A2.5 2.5 0 0 1 5.5 3H11v16H5.5A2.5 2.5 0 0 0 3 21.5z"/><path d="M21 5.5A2.5 2.5 0 0 0 18.5 3H13v16h5.5A2.5 2.5 0 0 1 21 21.5z"/>',
  meditation: '<circle cx="12" cy="6" r="2.6"/><path d="M12 9v5"/><path d="M8 20l4-6 4 6"/><path d="M5 13h14"/>',
  photo: '<rect x="3" y="7" width="18" height="13" rx="2"/><circle cx="12" cy="13.5" r="3.2"/><path d="M8 7l1.4-2.5h5.2L16 7"/>',
  alcohol: '<path d="M7 4h10l-1 5a4 4 0 0 1-8 0z"/><path d="M12 13v7"/><path d="M8.5 20h7"/>',
  bed: '<path d="M3 18v-6h18v6"/><path d="M3 12V8"/><circle cx="8" cy="10" r="2"/><path d="M11 12h10"/>',
  tick: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.6 2.5L16 9.5"/>',
  camera: '<rect x="3" y="7" width="18" height="13" rx="2"/><circle cx="12" cy="13.5" r="3.2"/><path d="M8 7l1.4-2.5h5.2L16 7"/>',
  warn: '<path d="M12 3l9 16H3z"/><path d="M12 9v5"/><path d="M12 17h.01"/>',
  stack: '<rect x="3" y="6" width="15" height="13" rx="2"/><path d="M21 8v9"/><path d="M3 16l4-3 4 3 3-2 4 3"/>',
  split: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M12 3v18"/>',
  people: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/>',
  trash: '<path d="M4 7h16"/><path d="M9 7V5h6v2"/><path d="M6 7l1 13h10l1-13"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  download: '<path d="M12 4v11"/><path d="M8 11l4 4 4-4"/><path d="M4 20h16"/>'
};

const svg = (d) => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;

/* ------------------------------------------------------- persistent state */

const STORE_KEY = "75.state.v1";

function blankState() {
  return {
    tier: null,
    start: null,          // [year, month, day] civil date — no time, no zone
    totalDays: 75,
    highestDay: 1,        // never let the count regress (see currentDay)
    bodyWeightLb: null,
    days: {},             // dayNumber -> { checks:{}, counts:{}, rest:bool }
    friends: [],
    shareProgress: false,
    theme: null           // null = follow the system
  };
}

let state = load();

function load() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (raw) return Object.assign(blankState(), JSON.parse(raw));
  } catch (_) { /* private mode, blocked storage — fall through */ }
  return blankState();
}

/**
 * Written synchronously on every change. The payload is a few KB at most (photos live in
 * IndexedDB), and debouncing it loses the write when someone taps and immediately closes
 * the tab.
 */
function save() {
  try { localStorage.setItem(STORE_KEY, JSON.stringify(state)); }
  catch (_) { toast("Couldn't save — device storage is full or blocked."); }
}

/* --------------------------------------------------------- photo storage */

const DB_NAME = "75.photos";
const DB_STORE = "photos";
let dbPromise = null;

function db() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    if (!("indexedDB" in window)) return reject(new Error("no indexeddb"));
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const store = req.result.createObjectStore(DB_STORE, { keyPath: "id", autoIncrement: true });
      store.createIndex("day", "day");
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

async function putPhoto(record) {
  const d = await db();
  return new Promise((resolve, reject) => {
    const tx = d.transaction(DB_STORE, "readwrite");
    const req = tx.objectStore(DB_STORE).add(record);
    req.onsuccess = () => resolve(req.result);
    tx.onerror = () => reject(tx.error);
  });
}

async function allPhotos() {
  try {
    const d = await db();
    return await new Promise((resolve, reject) => {
      const req = d.transaction(DB_STORE, "readonly").objectStore(DB_STORE).getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
  } catch (_) {
    return [];
  }
}

async function deletePhoto(id) {
  const d = await db();
  return new Promise((resolve, reject) => {
    const tx = d.transaction(DB_STORE, "readwrite");
    tx.objectStore(DB_STORE).delete(id);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
}

/** Photos are cached in memory with object URLs so screens can render synchronously. */
let photos = [];
const urls = new Map();

async function refreshPhotos() {
  photos = (await allPhotos()).sort((a, b) => a.attempt - b.attempt || a.day - b.day || a.ts - b.ts);
  for (const p of photos) {
    if (!urls.has(p.id)) urls.set(p.id, URL.createObjectURL(p.blob));
  }
}

const photoURL = (p) => urls.get(p.id) || "";

/* ------------------------------------------------------------- backup file */

/* Backups are a store-only ZIP rather than JSON with base64 photos. A full challenge can
   hold 75+ JPEGs; base64 inflates them by a third and would mean building one enormous
   string, which is exactly what fails on a phone at day 70 when the backup matters most.
   Stored entries keep the JPEGs byte-for-byte, and the file opens in any zip tool. */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[i] = c >>> 0;
  }
  return t;
})();

function crc32(bytes) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

function dosStamp(d) {
  return {
    time: ((d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)) & 0xFFFF,
    date: (((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()) & 0xFFFF
  };
}

/** entries: [{ name, data: Uint8Array }] -> Blob */
function zipStore(entries) {
  const enc = new TextEncoder();
  const { time, date } = dosStamp(new Date());
  const parts = [];
  const central = [];
  let offset = 0;

  for (const e of entries) {
    const name = enc.encode(e.name);
    const crc = crc32(e.data);
    const h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true);
    h.setUint16(4, 20, true);
    h.setUint16(6, 0x0800, true);          // UTF-8 names
    h.setUint16(8, 0, true);               // stored, no compression
    h.setUint16(10, time, true);
    h.setUint16(12, date, true);
    h.setUint32(14, crc, true);
    h.setUint32(18, e.data.length, true);
    h.setUint32(22, e.data.length, true);
    h.setUint16(26, name.length, true);
    h.setUint16(28, 0, true);
    parts.push(new Uint8Array(h.buffer), name, e.data);
    central.push({ name, crc, size: e.data.length, offset });
    offset += 30 + name.length + e.data.length;
  }

  const cdStart = offset;
  for (const c of central) {
    const h = new DataView(new ArrayBuffer(46));
    h.setUint32(0, 0x02014b50, true);
    h.setUint16(4, 20, true);
    h.setUint16(6, 20, true);
    h.setUint16(8, 0x0800, true);
    h.setUint16(10, 0, true);
    h.setUint16(12, time, true);
    h.setUint16(14, date, true);
    h.setUint32(16, c.crc, true);
    h.setUint32(20, c.size, true);
    h.setUint32(24, c.size, true);
    h.setUint16(28, c.name.length, true);
    h.setUint32(42, c.offset, true);
    parts.push(new Uint8Array(h.buffer), c.name);
    offset += 46 + c.name.length;
  }

  const eocd = new DataView(new ArrayBuffer(22));
  eocd.setUint32(0, 0x06054b50, true);
  eocd.setUint16(8, central.length, true);
  eocd.setUint16(10, central.length, true);
  eocd.setUint32(12, offset - cdStart, true);
  eocd.setUint32(16, cdStart, true);
  parts.push(new Uint8Array(eocd.buffer));

  return new Blob(parts, { type: "application/zip" });
}

function zipRead(buffer) {
  const dv = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  let eocd = -1;
  const floor = Math.max(0, buffer.byteLength - 22 - 65535);
  for (let i = buffer.byteLength - 22; i >= floor; i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("That file isn't a 75 backup.");

  const count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  const dec = new TextDecoder();
  const out = [];
  for (let i = 0; i < count; i++) {
    if (dv.getUint32(p, true) !== 0x02014b50) throw new Error("That backup file is damaged.");
    if (dv.getUint16(p + 10, true) !== 0) throw new Error("That backup was written by a different tool.");
    const nameLen = dv.getUint16(p + 28, true);
    const extraLen = dv.getUint16(p + 30, true);
    const cmtLen = dv.getUint16(p + 32, true);
    const size = dv.getUint32(p + 24, true);
    const crc = dv.getUint32(p + 16, true);
    const lho = dv.getUint32(p + 42, true);
    const name = dec.decode(bytes.subarray(p + 46, p + 46 + nameLen));
    const start = lho + 30 + dv.getUint16(lho + 26, true) + dv.getUint16(lho + 28, true);
    const data = bytes.subarray(start, start + size);
    if (crc32(data) !== crc) throw new Error("That backup is damaged, so nothing was changed.");
    out.push({ name, data });
    p += 46 + nameLen + extraLen + cmtLen;
  }
  return out;
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

async function exportBackup() {
  toast("Preparing backup\u2026");
  const manifest = {
    app: "75", format: 1,
    exported: new Date().toISOString(),
    state, photos: []
  };
  const entries = [];
  for (const p of photos) {
    const file = `photos/day${String(p.day).padStart(2, "0")}-a${p.attempt}-${p.pose.toLowerCase()}-${p.id}.jpg`;
    entries.push({ name: file, data: new Uint8Array(await p.blob.arrayBuffer()) });
    manifest.photos.push({ file, day: p.day, attempt: p.attempt, pose: p.pose, ts: p.ts });
  }
  entries.unshift({
    name: "backup.json",
    data: new TextEncoder().encode(JSON.stringify(manifest, null, 2))
  });
  const blob = zipStore(entries);
  downloadBlob(blob, `75-backup-${new Date().toISOString().slice(0, 10)}.zip`);
  const mb = (blob.size / 1048576).toFixed(1);
  toast(`Backup saved \u2014 ${photos.length} ${photos.length === 1 ? "photo" : "photos"}, ${mb} MB.`);
}

async function importBackup(file) {
  const entries = zipRead(await file.arrayBuffer());
  const manifestEntry = entries.find((e) => e.name === "backup.json");
  if (!manifestEntry) throw new Error("This doesn't look like a 75 backup.");
  const manifest = JSON.parse(new TextDecoder().decode(manifestEntry.data));
  if (manifest.app !== "75" || !manifest.state) throw new Error("This doesn't look like a 75 backup.");

  // Everything is validated before anything is deleted, so a bad file can't destroy
  // the data that is already here.
  const byName = new Map(entries.map((e) => [e.name, e.data]));
  for (const p of photos) { try { await deletePhoto(p.id); } catch (_) {} }
  urls.forEach((u) => URL.revokeObjectURL(u));
  urls.clear();
  photos = [];

  let restored = 0;
  for (const rec of (manifest.photos || [])) {
    const data = byName.get(rec.file);
    if (!data) continue;
    await putPhoto({
      day: rec.day, attempt: rec.attempt, pose: rec.pose, ts: rec.ts,
      blob: new Blob([data], { type: "image/jpeg" })
    });
    restored++;
  }

  state = Object.assign(blankState(), manifest.state);
  save();
  await refreshPhotos();
  boot();
  toast(`Restored \u2014 ${restored} ${restored === 1 ? "photo" : "photos"}.`);
}

/* -------------------------------------------------------------- day math */

/** Today as a civil date in the device's current zone. */
function todayCivil() {
  const d = new Date();
  return [d.getFullYear(), d.getMonth() + 1, d.getDate()];
}

/**
 * Which day of the challenge today is.
 *
 * Both ends are civil dates compared through Date.UTC, so the difference is always an
 * exact number of calendar days: unaffected by daylight saving, and unaffected by the
 * device moving between time zones. Clamped so it can never run backwards — crossing the
 * date line westward repeats a local date, and a day already lived shouldn't return.
 */
function currentDay() {
  if (!state.start) return 1;
  const [sy, sm, sd] = state.start;
  const [ty, tm, td] = todayCivil();
  const elapsed = Math.round((Date.UTC(ty, tm - 1, td) - Date.UTC(sy, sm - 1, sd)) / 86400000);
  const fromCalendar = Math.min(Math.max(elapsed + 1, 1), state.totalDays);
  return Math.min(Math.max(fromCalendar, state.highestDay || 1), state.totalDays);
}

/** Records the furthest day reached, so the clamp above has something to hold. */
function advanceDay() {
  const d = currentDay();
  if (d > (state.highestDay || 1)) { state.highestDay = d; save(); }
  return d;
}

const tier = () => TIERS[state.tier] || TIERS.soft;

function dayRecord(n) {
  if (!state.days[n]) state.days[n] = { checks: {}, counts: {}, rest: false };
  const r = state.days[n];
  r.checks = r.checks || {};
  r.counts = r.counts || {};
  return r;
}

/* --------------------------------------------------------- goals & totals */

function goalFor(task) {
  if (task.goal.fixed != null) return task.goal.fixed;
  if (task.goal.litres != null) return task.goal.litres;
  if (task.goal.halfBodyWeightOz) {
    const lb = state.bodyWeightLb || 160;
    return Math.round(((lb / 2) / OZ_PER_L) * 100) / 100;   // half body weight in oz -> litres
  }
  return 1;
}

const fmtAmount = (v, task) => (task.dec ? v.toFixed(task.dec) : String(Math.round(v))) + task.unit;

function taskDone(task, rec) {
  if (task.type === "check") return !!rec.checks[task.id];
  return (rec.counts[task.id] || 0) >= goalFor(task);
}

/** A planned 75 Soft rest day excuses the workout and nothing else. */
function requiredTasks(rec) {
  const t = tier();
  if (t.restDay && rec.rest) return t.tasks.filter((x) => x.id !== "workout");
  return t.tasks;
}

function dayComplete(n) {
  const rec = state.days[n];
  if (!rec) return false;
  const req = requiredTasks(rec);
  return req.length > 0 && req.every((t) => taskDone(t, rec));
}

function completionFraction(rec) {
  const req = requiredTasks(rec);
  if (!req.length) return 0;
  return req.filter((t) => taskDone(t, rec)).length / req.length;
}

const completedDays = () => {
  let n = 0;
  for (let d = 1; d <= state.totalDays; d++) if (dayComplete(d)) n++;
  return n;
};

/** Elapsed days that were never completed. Drives Medium's budget and Hard's reset. */
function missedDays() {
  const last = currentDay() - 1;
  let n = 0;
  for (let d = 1; d <= last; d++) if (!dayComplete(d)) n++;
  return n;
}

function streak() {
  let n = 0;
  for (let d = currentDay(); d >= 1; d--) {
    if (dayComplete(d)) n++;
    else if (d !== currentDay()) break;        // today still in progress doesn't break it
  }
  return n;
}

const isMilestoneDay = (n) => tier().photoCadence === "daily" || n === 1 || n === state.totalDays;
const photosForDay = (n) => photos.filter((p) => p.day === n && p.attempt === attemptNumber());
const attemptNumber = () => state.attempt || 1;

/* ------------------------------------------------------------------- views */

const $ = (sel) => document.querySelector(sel);
const screenEl = $("#screen");
let tab = "today";

const TITLES = { today: "Today", photos: "Photos", compare: "Compare", friends: "Friends" };

function render() {
  const views = { today: viewToday, photos: viewPhotos, compare: viewCompare, friends: viewFriends };
  $("#screenTitle").textContent = TITLES[tab];
  screenEl.innerHTML = views[tab]();
  document.querySelectorAll(".tab").forEach((b) =>
    b.setAttribute("aria-selected", String(b.dataset.tab === tab)));
  if (tab === "compare") wireCompare();
}

/* --- Today --- */

function viewToday() {
  const day = currentDay();
  const rec = dayRecord(day);
  const t = tier();
  const f = completionFraction(rec);
  const C = 2 * Math.PI * 68;
  const done = completedDays();

  let h = `
    <div class="ring-wrap"><div class="ring">
      <svg viewBox="0 0 156 156">
        <circle class="track" cx="78" cy="78" r="68"/>
        <circle class="fill" cx="78" cy="78" r="68" stroke-linecap="round"
          stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - f)).toFixed(1)}"/>
      </svg>
      <div class="ring-mid">
        <div class="ring-day">${day}</div>
        <div class="ring-of">of ${state.totalDays}</div>
      </div>
    </div></div>`;

  const third = t.failure.kind === "budget"
    ? `<div class="stat"><b>${Math.max(0, t.failure.allowed - missedDays())}</b><span>Misses left</span></div>`
    : `<div class="stat"><b>${Math.round((done / state.totalDays) * 100)}%</b><span>Overall</span></div>`;

  h += `<div class="stats">
      <div class="stat"><b>${streak()}</b><span>Streak</span></div>
      <div class="stat"><b>${done}</b><span>Completed</span></div>
      ${third}
    </div>`;

  if (attemptNumber() > 1) h += `<p class="attempt-line">Attempt ${attemptNumber()}</p>`;

  if (t.failure.kind === "restart" && missedDays() > 0) {
    h += `<div class="notice">
        <h4>A day went unfinished</h4>
        <p>75 Hard has no grace days — the rule is to start again at Day 1. Your photos and
           previous days are kept.</p>
        <button class="btn btn-warn btn-sm" data-act="restart">Restart at Day 1</button>
      </div>`;
  }

  h += '<div class="card">';
  for (const task of t.tasks) {
    const excused = t.restDay && rec.rest && task.id === "workout";
    if (excused) {
      h += `<div class="row" data-done="true" data-excused="true">
          <span class="row-glyph">${svg(ICON[task.icon])}</span>
          <span class="row-label">${task.title}<span class="row-note">Excused — rest day</span></span>
          <span class="row-check">${svg(ICON.tick)}</span></div>`;
    } else if (task.type === "check") {
      h += `<button class="row" data-act="check" data-id="${task.id}" data-done="${taskDone(task, rec)}">
          <span class="row-glyph">${svg(ICON[task.icon])}</span>
          <span class="row-label"><span class="row-title">${task.title}</span>${task.note ? `<span class="row-note">${task.note}</span>` : ""}</span>
          <span class="row-check">${svg(ICON.tick)}</span></button>`;
    } else {
      const goal = goalFor(task);
      const cur = rec.counts[task.id] || 0;
      h += `<div class="counter" data-done="${taskDone(task, rec)}">
          <div class="counter-top">
            <span class="row-glyph">${svg(ICON[task.icon])}</span>
            <span class="row-label"><span class="row-title">${task.title}</span>${task.note ? `<span class="row-note">${task.note}</span>` : ""}</span>
            <span class="counter-amt">${fmtAmount(cur, task)} / ${fmtAmount(goal, task)}</span>
          </div>
          <div class="counter-ctrls">
            <button class="step" data-act="dec" data-id="${task.id}" aria-label="Less ${task.title}">${svg(ICON.minus)}</button>
            <span class="bar"><i style="width:${Math.min(100, (cur / goal) * 100)}%"></i></span>
            <button class="step" data-act="inc" data-id="${task.id}" aria-label="More ${task.title}">${svg(ICON.plus)}</button>
          </div></div>`;
    }
  }
  h += "</div>";

  if (t.photoCadence === "milestone") {
    const shot = photosForDay(day).length > 0;
    const milestone = day === 1 || day === state.totalDays;
    const hot = milestone && !shot;
    h += `<div class="flag${hot ? " hot" : ""}">
        <h4>${svg(shot ? ICON.tick : ICON.camera)}${milestone ? `Day ${day} photo` : "Progress photo"}</h4>
        <p>${milestone
          ? `${t.name} asks for a photo on Day 1 and Day ${state.totalDays}. This is one of them.`
          : "Not required today. A weekly shot makes the before-and-after much stronger."}</p>
        <button class="btn ${hot ? "btn-primary" : "btn-ghost"} btn-sm" data-act="camera">
          ${shot ? "Take another" : "Take photo"}</button>
      </div>`;
  }

  if (t.restDay) {
    h += `<div class="card card-pad">
        <div class="switch-row">
          <span class="row-glyph">${svg(ICON.bed)}</span>
          <span class="row-label">Weekly rest day</span>
          <button class="switch" role="switch" aria-checked="${!!rec.rest}" aria-label="Weekly rest day" data-act="rest"></button>
        </div>
        <p class="fine">75 Soft allows one active-recovery day a week in place of the workout.
           Everything else on the list still counts.</p>
      </div>`;
  }

  return h;
}

/* --- Photos --- */

let selectedPose = "Front";

const poseSeg = (dark) => `<div class="seg${dark ? " seg-dark" : ""}" role="group" aria-label="Pose">` +
  POSES.map((p) => `<button data-act="pose" data-pose="${p}" aria-pressed="${selectedPose === p}">${p}</button>`).join("") +
  "</div>";

function viewPhotos() {
  const mine = photos.filter((p) => p.pose === selectedPose);
  let h = poseSeg(false);

  if (!mine.length) {
    return h + `<div class="empty">
        ${svg(ICON.stack)}
        <h3>No ${selectedPose.toLowerCase()} photos yet</h3>
        <p>Take one and it'll appear here. The next one lines up against it automatically.</p>
        <button class="btn btn-primary" data-act="camera">Take photo</button>
      </div>`;
  }

  h += '<div class="grid">';
  for (const p of mine) {
    h += `<button class="shot${isMilestoneDay(p.day) ? " is-milestone" : ""}" data-act="view" data-id="${p.id}">
        <img src="${photoURL(p)}" alt="Day ${p.day}, ${p.pose.toLowerCase()}" loading="lazy">
        <b>DAY ${p.day}</b></button>`;
  }
  h += "</div>";
  h += `<p class="fine">${mine.length} ${mine.length === 1 ? "photo" : "photos"}. Stored on this device only.</p>`;
  return h;
}

/* --- Compare --- */

let cmpBefore = null, cmpAfter = null, cmpFrac = 50;

function viewCompare() {
  const mine = photos.filter((p) => p.pose === selectedPose);
  let h = poseSeg(false);

  if (mine.length < 2) {
    return h + `<div class="empty">
        ${svg(ICON.split)}
        <h3>Two photos needed</h3>
        <p>Once you have two ${selectedPose.toLowerCase()} photos you can slide between any
           pair of days.</p>
        <button class="btn btn-primary" data-act="camera">Take photo</button>
      </div>`;
  }

  if (!mine.some((p) => p.id === cmpBefore)) cmpBefore = mine[0].id;
  if (!mine.some((p) => p.id === cmpAfter)) cmpAfter = mine[mine.length - 1].id;
  const before = mine.find((p) => p.id === cmpBefore);
  const after = mine.find((p) => p.id === cmpAfter);

  h += `<div class="pickers">
      <button class="picker" data-act="cycle" data-side="before"><span>Before</span><b>Day ${before.day}</b></button>
      <span class="arrow">${svg(ICON.arrow)}</span>
      <button class="picker" data-act="cycle" data-side="after"><span>After</span><b>Day ${after.day}</b></button>
    </div>
    <div class="compare" id="cmp" style="--f:${cmpFrac}%">
      <img src="${photoURL(after)}" alt="Day ${after.day}">
      <img class="before" src="${photoURL(before)}" alt="Day ${before.day}">
      <span class="tag l">DAY ${before.day}</span>
      <span class="tag r">DAY ${after.day}</span>
      <div class="divider"></div>
    </div>
    <button class="btn btn-ghost btn-block" data-act="export">Save comparison image</button>
    <p class="fine">Drag the divider. Saving writes a single side-by-side image to your
       downloads — nothing is uploaded.</p>`;
  return h;
}

function wireCompare() {
  const box = $("#cmp");
  if (!box) return;
  let dragging = false;
  const set = (x) => {
    const r = box.getBoundingClientRect();
    cmpFrac = Math.max(0, Math.min(100, ((x - r.left) / r.width) * 100));
    box.style.setProperty("--f", cmpFrac + "%");
  };
  box.addEventListener("pointerdown", (e) => { dragging = true; box.setPointerCapture(e.pointerId); set(e.clientX); });
  box.addEventListener("pointermove", (e) => { if (dragging) set(e.clientX); });
  box.addEventListener("pointerup", () => { dragging = false; });
  box.addEventListener("pointercancel", () => { dragging = false; });
}

async function exportComparison() {
  const mine = photos.filter((p) => p.pose === selectedPose);
  const before = mine.find((p) => p.id === cmpBefore);
  const after = mine.find((p) => p.id === cmpAfter);
  if (!before || !after) return;

  const [a, b] = await Promise.all([loadImage(photoURL(before)), loadImage(photoURL(after))]);
  const h = Math.max(a.naturalHeight, b.naturalHeight);
  const aw = Math.round(a.naturalWidth * (h / a.naturalHeight));
  const bw = Math.round(b.naturalWidth * (h / b.naturalHeight));
  const canvas = document.createElement("canvas");
  canvas.width = aw + bw;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(a, 0, 0, aw, h);
  ctx.drawImage(b, aw, 0, bw, h);

  ctx.font = `700 ${Math.round(h * 0.035)}px Helvetica, Arial, sans-serif`;
  ctx.fillStyle = "rgba(0,0,0,.6)";
  ctx.textBaseline = "top";
  const label = (text, x) => {
    const m = ctx.measureText(text);
    const pad = Math.round(h * 0.012);
    ctx.fillStyle = "rgba(0,0,0,.6)";
    ctx.fillRect(x, pad, m.width + pad * 2, Math.round(h * 0.05));
    ctx.fillStyle = "#fff";
    ctx.fillText(text, x + pad, pad * 2);
  };
  label(`DAY ${before.day}`, Math.round(h * 0.012));
  label(`DAY ${after.day}`, aw + Math.round(h * 0.012));

  canvas.toBlob((blob) => {
    if (!blob) return toast("Couldn't build the image.");
    downloadBlob(blob, `75-day${before.day}-vs-day${after.day}.jpg`);
    toast("Comparison saved.");
  }, "image/jpeg", 0.9);
}

const loadImage = (src) => new Promise((res, rej) => {
  const img = new Image();
  img.onload = () => res(img);
  img.onerror = rej;
  img.src = src;
});

/* --- Friends --- */

function viewFriends() {
  let h = `<div class="card card-pad">
      <div class="switch-row">
        <span class="row-label">Share my progress</span>
        <button class="switch" role="switch" aria-checked="${!!state.shareProgress}" aria-label="Share my progress" data-act="share"></button>
      </div>
      <p class="fine">When this is on, the people you add can see your day count and streak —
         never your photos. Photos only leave this device if you save a comparison and send it
         yourself.</p>
    </div>`;

  if (!state.friends.length) {
    h += `<div class="empty">
        ${svg(ICON.people)}
        <h3>No one added yet</h3>
        <p>Add a friend by phone number to keep each other honest.</p>
        <button class="btn btn-primary" data-act="addFriend">Add friend</button>
      </div>`;
  } else {
    h += '<div class="card">';
    for (const f of state.friends) {
      const initials = f.name.trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase() || "?";
      h += `<div class="person">
          <span class="avatar">${initials}</span>
          <span class="who"><b>${escapeHTML(f.name)}</b><span>${escapeHTML(f.phone)}</span></span>
          <button class="remove" data-act="removeFriend" data-id="${f.id}" aria-label="Remove ${escapeHTML(f.name)}">${svg(ICON.trash)}</button>
        </div>`;
    }
    h += "</div>";
    h += `<button class="btn btn-ghost btn-block" data-act="addFriend">Add friend</button>`;
  }

  h += `<p class="fine">Everyone you add is stored on this device. Sharing with their phone
     needs a server, which this build doesn't have yet — so nothing is sent anywhere.</p>`;
  return h;
}

const escapeHTML = (s) => String(s).replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

/* ------------------------------------------------------------- the camera */


/**
 * Why the camera didn't open. getUserMedia fails for several unrelated reasons and they
 * need different fixes, so say which one it was rather than "not available".
 *
 * The browser only exposes navigator.mediaDevices in a secure context, so an http:// origin
 * fails before any permission prompt — the single most likely surprise when deploying.
 */
function cameraFailureReason(err) {
  const name = err && err.name;
  if (name === "NotAllowedError") {
    // Also what an iframe without a camera allow-attribute reports.
    return window.self !== window.top
      ? "This page is embedded, and the camera is blocked here."
      : "Camera access was declined. Re-allow it in your browser's site settings.";
  }
  if (name === "NotFoundError" || name === "DevicesNotFoundError") return "No camera found on this device.";
  if (name === "NotReadableError" || name === "TrackStartError") return "The camera is already in use by another app.";
  if (name === "OverconstrainedError") return "This camera doesn't support the requested format.";
  if (!window.isSecureContext) return "The camera needs a secure connection. Open this page over https.";
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return "This browser can't open the camera.";
  return "The camera couldn't be opened.";
}

const camera = {
  stream: null,
  facing: "user",
  captured: null,
  pose: "Front",

  async open() {
    this.pose = selectedPose;
    $("#camera").hidden = false;
    $("#camDay").textContent = `Day ${currentDay()} of ${state.totalDays}`;
    renderPoseSeg();
    this.updateGhost();
    await this.start();
  },

  async start() {
    const video = $("#cam");
    const unavailable = $("#camUnavailable");
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        throw new Error("unsupported");
      }
      this.stop();
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: this.facing, width: { ideal: 1440 }, height: { ideal: 1920 } },
        audio: false
      });
      video.srcObject = this.stream;
      video.classList.toggle("mirror", this.facing === "user");
      video.hidden = false;
      unavailable.hidden = true;
      $("#shutter").hidden = false;
      $("#camFlip").hidden = false;
      await video.play().catch(() => {});
    } catch (err) {
      video.hidden = true;
      unavailable.hidden = false;
      $("#shutter").hidden = true;
      $("#camFlip").hidden = true;
      $("#camUnavailableMsg").textContent = cameraFailureReason(err);
    }
  },

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
  },

  close() {
    this.stop();
    $("#camera").hidden = true;
    this.captured = null;
    $("#review").hidden = true;
  },

  /** The previous photo of this pose, shown over the feed so framing stays consistent. */
  updateGhost() {
    const prior = photos.filter((p) => p.pose === this.pose).slice(-1)[0];
    const ghost = $("#ghost");
    const controls = $("#ghostControls");
    if (!prior) {
      ghost.hidden = true;
      controls.hidden = true;
      return;
    }
    ghost.src = photoURL(prior);
    ghost.hidden = $("#ghostToggle").getAttribute("aria-pressed") !== "true";
    controls.hidden = false;
    this.applyGhostStyle();
  },

  applyGhostStyle() {
    const ghost = $("#ghost");
    const align = $("#alignToggle").getAttribute("aria-pressed") === "true";
    ghost.classList.toggle("align", align);
    ghost.style.opacity = align ? "1" : String($("#ghostOpacity").value / 100);
    $("#ghostOpacity").hidden = align;
    $("#alignHint").hidden = !align;
  },

  capture() {
    const video = $("#cam");
    if (!video.videoWidth) return;
    const canvas = $("#shutterCanvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext("2d");
    if (this.facing === "user") {            // match what the viewfinder showed
      ctx.translate(canvas.width, 0);
      ctx.scale(-1, 1);
    }
    ctx.drawImage(video, 0, 0);
    canvas.toBlob((blob) => blob && this.review(blob), "image/jpeg", 0.88);
  },

  review(blob) {
    this.captured = blob;
    const img = $("#reviewImg");
    if (img.dataset.url) URL.revokeObjectURL(img.dataset.url);
    const url = URL.createObjectURL(blob);
    img.dataset.url = url;
    img.src = url;
    $("#review").hidden = false;
  },

  async save() {
    if (!this.captured) return;
    const day = currentDay();
    try {
      await putPhoto({
        day, attempt: attemptNumber(), pose: this.pose,
        ts: Date.now(), blob: this.captured
      });
    } catch (_) {
      toast("Couldn't save the photo — device storage may be full.");
      return;
    }
    await refreshPhotos();

    if (tier().photoCadence === "daily") {
      dayRecord(day).checks.photo = true;
      save();
    }
    this.close();
    selectedPose = this.pose;
    render();
    toast(`Day ${day} ${this.pose.toLowerCase()} photo saved.`);
  }
};

function renderPoseSeg() {
  $("#poseSeg").innerHTML = POSES
    .map((p) => `<button data-pose="${p}" aria-pressed="${camera.pose === p}">${p}</button>`)
    .join("");
}

/* ---------------------------------------------------------------- chrome */

let toastTimer = null;
function toast(msg) {
  const el = $("#toast");
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 2600);
}

function modal({ title, body, actions }) {
  $("#modalTitle").textContent = title;
  $("#modalBody").innerHTML = body || "";
  const wrap = $("#modalActions");
  wrap.innerHTML = "";
  for (const a of actions) {
    const btn = document.createElement("button");
    btn.className = "btn " + (a.style || "btn-ghost");
    btn.textContent = a.label;
    btn.addEventListener("click", () => {
      const keep = a.onClick && a.onClick();
      if (!keep) $("#modal").hidden = true;
    });
    wrap.appendChild(btn);
  }
  $("#modal").hidden = false;
}

function addFriendDialog() {
  modal({
    title: "Add friend",
    body: `<div class="field"><label for="fName">Name</label>
             <div class="field-row"><input id="fName" type="text" autocomplete="name" placeholder="Their name"></div></div>
           <div class="field"><label for="fPhone">Phone number</label>
             <div class="field-row"><input id="fPhone" type="tel" autocomplete="tel" placeholder="+1 555 000 0000"></div></div>
           <p class="fine">Saved on this device. No message is sent — connecting with their
              phone needs a server this build doesn't have yet.</p>`,
    actions: [
      { label: "Cancel" },
      {
        label: "Add", style: "btn-primary",
        onClick: () => {
          const name = $("#fName").value.trim();
          const phone = $("#fPhone").value.trim();
          if (!phone) { toast("A phone number is needed."); return true; }
          state.friends.push({ id: Date.now(), name: name || phone, phone });
          save();
          render();
        }
      }
    ]
  });
}

function settingsDialog() {
  const t = tier();
  modal({
    title: "Settings",
    body: `<p><b>${t.name}</b> — day ${currentDay()} of ${state.totalDays},
             started ${state.start ? state.start.slice().reverse().join("/") : "—"}.</p>
           <p>${photos.length} ${photos.length === 1 ? "photo" : "photos"} stored on this device.</p>
           <p>Everything here is saved in this browser. Clearing site data erases it, and it
              doesn't follow you to another device — so take a backup now and then.</p>`,
    actions: [
      { label: "Back up", style: "btn-primary", onClick: () => { exportBackup().catch(() => toast("Couldn't build the backup.")); } },
      { label: "Restore", onClick: () => { $("#restorePick").click(); } },
      { label: "Close" },
      {
        label: "Start over", style: "btn-warn",
        onClick: () => {
          modal({
            title: "Start over?",
            body: "<p>This erases your days, photos and friends on this device. It can't be undone.</p>",
            actions: [
              { label: "Keep my data" },
              {
                label: "Erase everything", style: "btn-warn",
                onClick: async () => {
                  for (const p of photos) { try { await deletePhoto(p.id); } catch (_) {} }
                  urls.forEach((u) => URL.revokeObjectURL(u));
                  urls.clear();
                  photos = [];
                  state = blankState();
                  try { localStorage.removeItem(STORE_KEY); } catch (_) {}
                  boot();
                }
              }
            ]
          });
          return true;
        }
      }
    ]
  });
}

/* ------------------------------------------------------------- onboarding */

let setupTier = "soft";

function renderSetup() {
  $("#tierCards").innerHTML = Object.entries(TIERS).map(([key, t]) => `
    <button class="tier-card" data-tier="${key}" aria-pressed="${setupTier === key}">
      <span class="tier-card-head">
        <h3>${t.name}</h3>
        <span class="mark">${svg(ICON.tick)}</span>
      </span>
      <span class="tier-tag">${t.tagline}</span>
      <ul class="tier-rules">${t.rules.map((r) => `<li>${r}</li>`).join("")}</ul>
    </button>`).join("");

  const needsWeight = TIERS[setupTier].tasks.some((x) => x.goal && x.goal.halfBodyWeightOz);
  $("#weightField").hidden = !needsWeight;
  $("#startBtn").textContent = `Start ${TIERS[setupTier].name}`;
}

function beginChallenge() {
  const needsWeight = TIERS[setupTier].tasks.some((x) => x.goal && x.goal.halfBodyWeightOz);
  let lb = null;
  if (needsWeight) {
    const raw = parseFloat($("#weightInput").value);
    if (!raw || raw <= 0) { toast("Enter your body weight to set the water goal."); return; }
    lb = $("#weightUnit").value === "kg" ? raw * LB_PER_KG : raw;
  }
  state = blankState();
  state.tier = setupTier;
  state.start = todayCivil();
  state.highestDay = 1;
  state.attempt = 1;
  state.bodyWeightLb = lb;
  save();
  boot();
}

function restartChallenge() {
  state.attempt = attemptNumber() + 1;
  state.start = todayCivil();
  state.highestDay = 1;
  state.days = {};
  save();
  render();
  toast("Restarted at Day 1. Your photos are kept.");
}

/* ------------------------------------------------------------------- boot */

function boot() {
  const ready = !!state.tier && !!state.start;
  $("#setup").hidden = ready;
  $("#app").hidden = !ready;
  if (ready) { advanceDay(); render(); } else { renderSetup(); }
}

/* events ------------------------------------------------------------------ */

document.querySelectorAll(".tab").forEach((b) =>
  b.addEventListener("click", () => {
    tab = b.dataset.tab;
    render();
    window.scrollTo(0, 0);   // the page scrolls, not the screen element
  }));

$("#settingsBtn").addEventListener("click", settingsDialog);

$("#tierCards").addEventListener("click", (e) => {
  const card = e.target.closest("[data-tier]");
  if (!card) return;
  setupTier = card.dataset.tier;
  renderSetup();
});
$("#startBtn").addEventListener("click", beginChallenge);

screenEl.addEventListener("click", (e) => {
  const el = e.target.closest("[data-act]");
  if (!el) return;
  const act = el.dataset.act;
  const day = currentDay();
  const rec = dayRecord(day);

  if (act === "check") {
    rec.checks[el.dataset.id] = !rec.checks[el.dataset.id];
  } else if (act === "inc" || act === "dec") {
    const task = tier().tasks.find((t) => t.id === el.dataset.id);
    const next = (rec.counts[task.id] || 0) + (act === "inc" ? task.step : -task.step);
    rec.counts[task.id] = Math.max(0, Math.round(next * 100) / 100);
  } else if (act === "rest") {
    rec.rest = !rec.rest;
  } else if (act === "share") {
    state.shareProgress = !state.shareProgress;
  } else if (act === "pose") {
    selectedPose = el.dataset.pose;
  } else if (act === "camera") {
    camera.open();
    return;
  } else if (act === "restart") {
    modal({
      title: "Restart at Day 1?",
      body: "<p>Your photos and previous days stay in your history. The day count starts again from today.</p>",
      actions: [{ label: "Not yet" }, { label: "Restart", style: "btn-warn", onClick: restartChallenge }]
    });
    return;
  } else if (act === "cycle") {
    const mine = photos.filter((p) => p.pose === selectedPose);
    const key = el.dataset.side === "before" ? "cmpBefore" : "cmpAfter";
    const cur = key === "cmpBefore" ? cmpBefore : cmpAfter;
    const i = mine.findIndex((p) => p.id === cur);
    const next = mine[(i + 1) % mine.length].id;
    if (key === "cmpBefore") cmpBefore = next; else cmpAfter = next;
  } else if (act === "export") {
    exportComparison();
    return;
  } else if (act === "view") {
    openViewer(Number(el.dataset.id));
    return;
  } else if (act === "addFriend") {
    addFriendDialog();
    return;
  } else if (act === "removeFriend") {
    const id = Number(el.dataset.id);
    state.friends = state.friends.filter((f) => f.id !== id);
  } else {
    return;
  }
  save();
  render();
});

/* full-screen viewer */
function openViewer(id) {
  const p = photos.find((x) => x.id === id);
  if (!p) return;
  const wrap = document.createElement("div");
  wrap.className = "viewer";
  wrap.innerHTML = `
    <img src="${photoURL(p)}" alt="Day ${p.day}, ${p.pose.toLowerCase()}">
    <button class="round-btn viewer-close" aria-label="Close">${svg('<path d="M6 6l12 12M18 6L6 18"/>')}</button>
    <div class="viewer-bar">
      <span class="meta">Day ${p.day} · ${p.pose} · ${new Date(p.ts).toLocaleDateString()}</span>
      <button class="btn btn-ghost-light btn-sm" data-del="1">Delete</button>
    </div>`;
  wrap.querySelector(".viewer-close").addEventListener("click", () => wrap.remove());
  wrap.querySelector("[data-del]").addEventListener("click", () => {
    modal({
      title: "Delete this photo?",
      body: "<p>It will be removed from this device permanently.</p>",
      actions: [
        { label: "Keep" },
        {
          label: "Delete", style: "btn-warn",
          onClick: async () => {
            try { await deletePhoto(p.id); } catch (_) {}
            const u = urls.get(p.id);
            if (u) { URL.revokeObjectURL(u); urls.delete(p.id); }
            await refreshPhotos();
            wrap.remove();
            render();
            toast("Photo deleted.");
          }
        }
      ]
    });
  });
  document.body.appendChild(wrap);
}

/* camera controls */
$("#camClose").addEventListener("click", () => camera.close());
$("#camFlip").addEventListener("click", async () => {
  camera.facing = camera.facing === "user" ? "environment" : "user";
  await camera.start();
});
$("#shutter").addEventListener("click", () => camera.capture());
$("#poseSeg").addEventListener("click", (e) => {
  const b = e.target.closest("[data-pose]");
  if (!b) return;
  camera.pose = b.dataset.pose;
  renderPoseSeg();
  camera.updateGhost();
});
$("#ghostToggle").addEventListener("click", (e) => {
  const on = e.currentTarget.getAttribute("aria-pressed") !== "true";
  e.currentTarget.setAttribute("aria-pressed", String(on));
  $("#ghost").hidden = !on;
  $("#alignToggle").hidden = !on;
  camera.applyGhostStyle();
});
$("#alignToggle").addEventListener("click", (e) => {
  const on = e.currentTarget.getAttribute("aria-pressed") !== "true";
  e.currentTarget.setAttribute("aria-pressed", String(on));
  camera.applyGhostStyle();
});
$("#ghostOpacity").addEventListener("input", () => camera.applyGhostStyle());
$("#filePick").addEventListener("change", (e) => {
  const file = e.target.files && e.target.files[0];
  if (file) camera.review(file);
  e.target.value = "";
});
$("#retake").addEventListener("click", () => {
  camera.captured = null;
  $("#review").hidden = true;
});
$("#usePhoto").addEventListener("click", () => camera.save());

$("#restorePick").addEventListener("change", (e) => {
  const file = e.target.files && e.target.files[0];
  e.target.value = "";
  if (!file) return;
  modal({
    title: "Restore this backup?",
    body: `<p><b>${escapeHTML(file.name)}</b></p>
           <p>This replaces the challenge, photos and friends currently on this device.
              It can't be undone, so back up first if there's anything here worth keeping.</p>`,
    actions: [
      { label: "Cancel" },
      {
        label: "Restore", style: "btn-warn",
        onClick: () => {
          importBackup(file).catch((err) => toast(err.message || "That backup couldn't be read."));
        }
      }
    ]
  });
});

$("#modal").addEventListener("click", (e) => {
  if (e.target === $("#modal")) $("#modal").hidden = true;
});
document.addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  if (!$("#modal").hidden) $("#modal").hidden = true;
  else if (!$("#review").hidden) { camera.captured = null; $("#review").hidden = true; }
  else if (!$("#camera").hidden) camera.close();
  else document.querySelector(".viewer")?.remove();
});

/* The day can change while the app sits open — at local midnight, or because the device
   moved zone or crossed a daylight-saving boundary. Re-check on wake and periodically. */
function checkDayChange() {
  if (!state.tier) return;
  const before = currentDay();
  advanceDay();
  if (currentDay() !== before) render();
}
document.addEventListener("visibilitychange", () => { if (!document.hidden) checkDayChange(); });
window.addEventListener("focus", checkDayChange);
setInterval(checkDayChange, 60000);

/* go */
refreshPhotos().then(boot);
