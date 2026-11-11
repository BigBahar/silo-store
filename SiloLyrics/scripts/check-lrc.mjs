#!/usr/bin/env node
// Linux-side check for the Swift LRC parser: same rules, run against real LRCLIB data.
// Usage: node check-lrc.mjs [--offline] ["Track" "Artist" "Album" durationSeconds]
// Port of Sources/SiloLyricsKit/LRCParser.swift; keep them in sync.

function parseTimestamp(tag) {
  const m = /^(\d+):(\d{1,2})(?:[.:](\d+))?$/.exec(tag);
  if (!m) return null;
  const s = Number(m[2]);
  if (s >= 60) return null;
  const frac = m[3] ? Number(m[3]) / 10 ** m[3].length : 0;
  return Number(m[1]) * 60 + s + frac;
}

export function parseLRC(raw) {
  const out = [];
  let offset = 0;
  raw.split(/\r?\n|\r/).forEach((line, order) => {
    let rest = line.trim();
    const stamps = [];
    for (;;) {
      if (!rest.startsWith("[")) break;
      const close = rest.indexOf("]");
      if (close < 0) break;
      const tag = rest.slice(1, close);
      const t = parseTimestamp(tag);
      if (t !== null) stamps.push(t);
      else if (/^offset:/i.test(tag) && !Number.isNaN(Number(tag.slice(7).trim()))) offset = Number(tag.slice(7).trim()) / 1000;
      else if (stamps.length === 0) { rest = ""; break; }
      else break;
      rest = rest.slice(close + 1);
    }
    if (!stamps.length) return;
    const text = rest.replace(/<[^>]*>/g, "").trim();
    for (const t of stamps) out.push({ time: Math.max(0, t - offset), text, order });
  });
  return out.sort((a, b) => a.time - b.time || a.order - b.order).map(({ time, text }) => ({ time, text }));
}

function assertEq(a, b, label) {
  const ok = JSON.stringify(a) === JSON.stringify(b);
  console.log(`${ok ? "ok  " : "FAIL"} ${label}`);
  if (!ok) { console.log("  got     ", JSON.stringify(a), "\n  expected", JSON.stringify(b)); process.exitCode = 1; }
}

function selfTest() {
  assertEq(parseLRC("[ar: X]\n[ti: S]\n[00:12.00] First\n[00:17.5]Second\n[01:02.345] Third"),
    [{ time: 12, text: "First" }, { time: 17.5, text: "Second" }, { time: 62.345, text: "Third" }], "basic + metadata");
  assertEq(parseLRC("[00:30.00][00:10.00]Chorus\n[00:20.00]\n"),
    [{ time: 10, text: "Chorus" }, { time: 20, text: "" }, { time: 30, text: "Chorus" }], "multi-stamp, empty line kept");
  assertEq(parseLRC("[offset:+500]\n[00:10.00]<00:10.00>Hel<00:10.40>lo"), [{ time: 9.5, text: "Hello" }], "offset + word tags");
  assertEq(parseLRC("no tags\n[xx:yy]nope\n[00:61.00]bad"), [], "garbage ignored");
}

async function live(args) {
  const [track, artist, album, duration] = args;
  const url = new URL("https://lrclib.net/api/get");
  Object.entries({ track_name: track, artist_name: artist, album_name: album, duration }).forEach(([k, v]) => url.searchParams.set(k, v));
  const res = await fetch(url, { headers: { "User-Agent": "SiloLyrics-check/1.0" } });
  console.log(`LRCLIB ${res.status} for ${track} - ${artist}`);
  if (!res.ok) { process.exitCode = 1; return; }
  const rec = await res.json();
  const lines = parseLRC(rec.syncedLyrics ?? "");
  const sorted = lines.every((l, i) => i === 0 || lines[i - 1].time <= l.time);
  console.log(`parsed ${lines.length} synced lines; sorted=${sorted}; first=${JSON.stringify(lines[0])}; last=${JSON.stringify(lines.at(-1))}`);
  if (!lines.length || !sorted) process.exitCode = 1;
}

selfTest();
const args = process.argv.slice(2).filter((a) => a !== "--offline");
if (!process.argv.includes("--offline") && args.length === 4) await live(args);
