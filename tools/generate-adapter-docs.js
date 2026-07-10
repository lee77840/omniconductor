#!/usr/bin/env node
'use strict';

/*
 * CONDUCTOR — doc generator from adapter metadata (ADR-042; ADR-040 slice 2).
 *
 * Reads adapters/<tool>/metadata.json (the single source for enumerable adapter
 * facts) and rewrites MARKED REGIONS in the docs below. Hand-editing inside a
 * marked region is futile — edit metadata.json and re-run this script.
 *
 * Regions:
 *   docs/ADAPTER-LIVE-VERIFICATION.md   <!-- generated:live-verification-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:adapter-outputs-table -->
 *
 * Usage:
 *   node tools/generate-adapter-docs.js           # rewrite regions in place
 *   node tools/generate-adapter-docs.js --check   # exit 1 if any region is out of date (CI)
 *
 * Exit codes: 0 = up to date / written, 1 = --check found drift, 2 = error.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
const CHECK = process.argv.includes('--check');

function die(msg) { process.stderr.write(`generate-adapter-docs: ${msg}\n`); process.exit(2); }

function loadMetadata() {
  return TOOLS.map((tool) => {
    const p = path.join(ROOT, 'adapters', tool, 'metadata.json');
    let m;
    try { m = JSON.parse(fs.readFileSync(p, 'utf8')); }
    catch (e) { die(`${p}: ${e.message}`); }
    if (m.tool !== tool) die(`${p}: tool field '${m.tool}' != directory '${tool}'`);
    return m;
  });
}

// ---- renderers -------------------------------------------------------------

function liveCell(m) {
  const lv = m.live_verification;
  if (lv.status === 'verified') {
    return `✅ **live-verified ${lv.date}** — ${lv.cli}${lv.note ? ` ${lv.note}` : ''}`;
  }
  return `🧪 ${lv.note || 'not yet run'}`;
}

function renderLiveVerificationTable(metas) {
  const rows = metas.map((m) => `| ${m.display_name} | ✅ | ${liveCell(m)} |`);
  return [
    '| Adapter | File emission | Live rule-loading |',
    '|---|---|---|',
    ...rows,
  ].join('\n');
}

function renderOutputsTable(metas) {
  const rows = metas.map((m) => {
    const outputs = m.outputs.map((o) => `\`${o.path}\``).join(' + ');
    // "(legacy)" qualifier keeps these rows compliant with the stale-token
    // allow_regex (ADR-039) — a bare legacy path here would read as a current claim.
    const legacy = m.legacy_paths.length ? m.legacy_paths.map((l) => `\`${l}\` (legacy)`).join(', ') : '—';
    const live = m.live_verification.status === 'verified'
      ? `✅ ${m.live_verification.date}`
      : '🧪 pending';
    const headless = `\`${m.headless_cli.invocation}\``;
    const alaCarte = m.install && m.install.ala_carte === 'block' ? 'marked block' : 'per-file';
    return `| ${m.display_name} | ${m.tier} | ${outputs} | ${legacy} | ${live} | ${headless} | ${alaCarte} |`;
  });
  return [
    '| Tool | Tier | Emitted outputs | Legacy paths (still read) | Live-verified | Headless CLI | À la carte (`--mode`) |',
    '|---|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

// ---- region splicing -------------------------------------------------------

function spliceRegion(file, name, body) {
  const p = path.join(ROOT, file);
  const src = fs.readFileSync(p, 'utf8');
  const open = `<!-- generated:${name} — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->`;
  const close = `<!-- /generated:${name} -->`;
  const start = src.indexOf(open);
  const end = src.indexOf(close);
  if (start === -1 || end === -1 || end < start) {
    die(`${file}: marked region '${name}' not found (need both open + close markers)`);
  }
  const next = src.slice(0, start + open.length) + '\n' + body + '\n' + src.slice(end);
  return { p, src, next, changed: next !== src };
}

function main() {
  const metas = loadMetadata();
  const jobs = [
    spliceRegion('docs/ADAPTER-LIVE-VERIFICATION.md', 'live-verification-table', renderLiveVerificationTable(metas)),
    spliceRegion('docs/COMPATIBILITY-MATRIX.md', 'adapter-outputs-table', renderOutputsTable(metas)),
  ];

  const drifted = jobs.filter((j) => j.changed);
  if (CHECK) {
    if (drifted.length) {
      for (const j of drifted) {
        process.stderr.write(`DRIFT: ${path.relative(ROOT, j.p)} generated region is out of date with adapters/*/metadata.json\n`);
      }
      process.stderr.write(`Run: node tools/generate-adapter-docs.js\n`);
      process.exit(1);
    }
    process.stdout.write('OK — generated doc regions match adapter metadata.\n');
    return;
  }

  for (const j of jobs) {
    if (j.changed) { fs.writeFileSync(j.p, j.next); process.stdout.write(`wrote ${path.relative(ROOT, j.p)}\n`); }
    else process.stdout.write(`up-to-date ${path.relative(ROOT, j.p)}\n`);
  }
}

main();
