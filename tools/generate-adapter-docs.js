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
 *   docs/ADAPTER-LIVE-VERIFICATION.md   <!-- generated:runtime-contract-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:adapter-outputs-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:portable-skills-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:hook-compiler-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:extension-trust-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:skill-proposals-table -->
 *   docs/COMPATIBILITY-MATRIX.md        <!-- generated:plugin-packaging-table -->
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
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode'];
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

function renderRuntimeContractTable(metas) {
  const rows = metas.map((m) => {
    const runtime = m.runtime_contract;
    const product = runtime.product.lifecycle === 'renamed'
      ? `${runtime.product.canonical_name} (adapter: ${m.display_name})`
      : runtime.product.canonical_name;
    const floors = runtime.version.capability_floors.length
      ? runtime.version.capability_floors.map((floor) => `${floor.capability} ≥ ${floor.minimum}`).join('<br>')
      : 'no documented numeric floor';
    const probe = `${runtime.probe.kind}; auth=${runtime.probe.requires_auth ? 'yes' : 'no'}, network=${runtime.probe.requires_network ? 'yes' : 'no'}`;
    return `| ${m.display_name} | ${product} · ${runtime.product.lifecycle} | ${runtime.auth.status} | ${floors} | ${probe} |`;
  });
  return [
    '| Adapter | Product lifecycle | Auth contract | Applicable version floors | Probe contract |',
    '|---|---|---|---|---|',
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

function renderPortableSkillsTable(metas) {
  const activationLabels = {
    'automatic-and-explicit': 'automatic + explicit',
    'automatic-with-consent': 'automatic + activation consent',
    'automatic-and-explicit-one-active': 'automatic + explicit; one active',
  };
  const rows = metas.map((m) => {
    const skills = m.agent_skills;
    const source = `[official](${skills.source.url}) (${skills.source.checked})`;
    return `| ${m.display_name} | \`${skills.project_path}\` | ${skills.path_status} | ${activationLabels[skills.activation] || skills.activation} | \`${skills.explicit_invocation}\` | ${source} |`;
  });
  return [
    '| Tool | Emitted project root | Path status | Activation | Example explicit invocation | First-party basis |',
    '|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

function renderHookCompilerTable(metas) {
  const label = (m, policy) => m.hook_compiler.native_policies.includes(policy)
    ? '✅ native'
    : '📘 rule fallback';
  const rows = metas.map((m) => {
    const hook = m.hook_compiler;
    const source = `[official](${hook.source.url}) (${hook.source.checked})`;
    return `| ${m.display_name} | \`${hook.config_path}\` | ${label(m, 'commit-current-work')} | ${label(m, 'commit-test-coverage')} | ${label(m, 'review-before-stop')} | ${source} |`;
  });
  return [
    '| Tool | Schema-aware config | CURRENT_WORK commit check | Test-coverage commit check | Review-before-stop | First-party basis |',
    '|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

function renderExtensionTrustTable(metas) {
  const rows = metas.map((m) => {
    const trust = m.extension_trust;
    const roots = trust.audit_roots.map((root) => `\`${root}\``).join(' + ');
    const controls = trust.native_controls.join(', ');
    const source = `[official](${trust.sources[0].url}) (${trust.sources[0].checked})`;
    return `| ${m.display_name} | ${roots} | ${controls} | ${trust.mcp_protocol_2026_07_28} | ${source} |`;
  });
  return [
    '| Tool | Project audit roots | Native trust controls | MCP 2026-07-28 boundary | First-party basis |',
    '|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

function renderSkillProposalsTable(metas) {
  const rows = metas.map((m) => {
    const proposal = m.skill_proposals;
    const source = `[official](${proposal.source.url}) (${proposal.source.checked})`;
    return `| ${m.display_name} | \`${proposal.opt_in_skill_path}\` | ${proposal.native_acceleration} | ${proposal.application} | ${source} |`;
  });
  return [
    '| Tool | Opt-in proposal skill | Native acceleration | Application boundary | First-party basis |',
    '|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

function renderPluginPackagingTable(metas) {
  const rows = metas.map((m) => {
    const packaging = m.plugin_packaging;
    const manifest = packaging.manifest_path ? `\`${packaging.manifest_path}\`` : '—';
    const native = packaging.native_components.length ? packaging.native_components.join(', ') : 'none';
    const source = `[official](${packaging.source.url}) (${packaging.source.checked})`;
    return `| ${m.display_name} | ${packaging.mode} | ${manifest} | ${native} | ${packaging.direct_install_required_for.join(', ')} | ${source} |`;
  });
  return [
    '| Tool | Package mode | Native manifest | Native components | Direct install still required for | First-party basis |',
    '|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

// ---- region splicing -------------------------------------------------------

function spliceRegion(file, name, body, sourceOverride) {
  const p = path.join(ROOT, file);
  const src = sourceOverride === undefined ? fs.readFileSync(p, 'utf8') : sourceOverride;
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
  const live = spliceRegion(
    'docs/ADAPTER-LIVE-VERIFICATION.md',
    'live-verification-table',
    renderLiveVerificationTable(metas),
  );
  const runtime = spliceRegion(
    'docs/ADAPTER-LIVE-VERIFICATION.md',
    'runtime-contract-table',
    renderRuntimeContractTable(metas),
    live.next,
  );
  const combinedLive = {
    p: live.p,
    src: live.src,
    next: runtime.next,
    changed: runtime.next !== live.src,
  };
  const outputs = spliceRegion(
    'docs/COMPATIBILITY-MATRIX.md',
    'adapter-outputs-table',
    renderOutputsTable(metas),
  );
  const skills = spliceRegion(
    'docs/COMPATIBILITY-MATRIX.md',
    'portable-skills-table',
    renderPortableSkillsTable(metas),
    outputs.next,
  );
  const hooks = spliceRegion(
    'docs/COMPATIBILITY-MATRIX.md',
    'hook-compiler-table',
    renderHookCompilerTable(metas),
    skills.next,
  );
  const trust = spliceRegion(
    'docs/COMPATIBILITY-MATRIX.md',
    'extension-trust-table',
    renderExtensionTrustTable(metas),
    hooks.next,
  );
  const proposals = spliceRegion(
    'docs/COMPATIBILITY-MATRIX.md',
    'skill-proposals-table',
    renderSkillProposalsTable(metas),
    trust.next,
  );
  const packaging = spliceRegion(
    'docs/COMPATIBILITY-MATRIX.md',
    'plugin-packaging-table',
    renderPluginPackagingTable(metas),
    proposals.next,
  );
  const combinedMatrix = {
    p: outputs.p,
    src: outputs.src,
    next: packaging.next,
    changed: packaging.next !== outputs.src,
  };
  const jobs = [
    combinedLive,
    combinedMatrix,
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
