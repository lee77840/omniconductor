'use strict';

/*
 * omniconductor doctor — read-only health check for an installed project (ADR-041).
 *
 * Anchors on <target>/.conductor-manifest.json and NEVER writes anything.
 * The bash adapters remain the single source of truth for install logic
 * (ADR-002/023/025) — doctor only inspects their output.
 *
 * Check groups:
 *   D1 manifest validity     — exists, parses, has version + emitted_files
 *   D2 version drift         — manifest version vs the running package version
 *   D3 file integrity        — every manifest-emitted file still exists
 *   D4 stale legacy paths    — adapter's legacy paths present in the target
 *   D5 hook validity         — emitted .json parse; emitted .sh executable + `bash -n`
 *   D6 doc-link liveness     — relative markdown links in emitted docs resolve
 *   D7 stale claims          — emitted files scanned against tools/stale-tokens.txt
 *
 * Severity: FAIL = broken install · WARN = degraded/attention · OK.
 * Exit codes: 0 = all OK · 1 = warnings only · 2 = failures (or unusable target).
 */

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');

function readPkgVersion() {
  try { return JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')).version || null; }
  catch { return null; }
}

function loadAdapterMetadata(adapter) {
  try { return JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', adapter, 'metadata.json'), 'utf8')); }
  catch { return null; }
}

// tools/stale-tokens.txt: pattern \t reason \t hint \t allow_regex?  (# = comment)
function loadStaleTokens() {
  let raw;
  try { raw = fs.readFileSync(path.join(ROOT, 'tools', 'stale-tokens.txt'), 'utf8'); }
  catch { return []; }
  const rules = [];
  for (const line of raw.split('\n')) {
    const l = line.replace(/\r$/, '');
    if (!l || l.startsWith('#')) continue;
    const [pattern, reason, hint, allow] = l.split('\t');
    if (!pattern) continue;
    rules.push({ pattern, reason: reason || '', hint: hint || '', allow: allow || null });
  }
  return rules;
}

function inferAdapter(manifest, targetAbs) {
  if (manifest && typeof manifest.adapter === 'string') return manifest.adapter;
  // Pre-0.8.0 claude manifests carry no adapter field — infer from footprint.
  if (fs.existsSync(path.join(targetAbs, '.claude', 'rules'))) return 'claude';
  return null;
}

function run(targetDir, opts) {
  const json = !!(opts && opts.json);
  const results = []; // {id, status: 'OK'|'WARN'|'FAIL', detail}
  const add = (id, status, detail) => results.push({ id, status, detail });

  const targetAbs = path.resolve(process.cwd(), targetDir || '.');
  const finish = () => {
    const counts = { OK: 0, WARN: 0, FAIL: 0 };
    for (const r of results) counts[r.status]++;
    if (json) {
      process.stdout.write(JSON.stringify({
        doctor: readPkgVersion(), target: targetAbs, checks: results, summary: counts,
      }, null, 2) + '\n');
    } else {
      for (const r of results) {
        const pad = r.status === 'OK' ? 'OK  ' : (r.status === 'WARN' ? 'WARN' : 'FAIL');
        process.stdout.write(`${pad} [${r.id}] ${r.detail}\n`);
      }
      process.stdout.write(`\n${counts.FAIL ? 'FAIL' : counts.WARN ? 'WARN' : 'OK'} — ${counts.OK} ok, ${counts.WARN} warn, ${counts.FAIL} fail (${targetAbs})\n`);
      if (counts.FAIL || counts.WARN) {
        process.stdout.write(`Re-install (safe: backups + manifest): npx omniconductor init --target=<tool> ${targetDir || '.'}\n`);
      }
    }
    return counts.FAIL ? 2 : (counts.WARN ? 1 : 0);
  };

  if (!fs.existsSync(targetAbs) || !fs.statSync(targetAbs).isDirectory()) {
    add('D1', 'FAIL', `target directory does not exist: ${targetAbs}`);
    return finish();
  }

  // ---- D1 manifest validity ------------------------------------------------
  const manifestPath = path.join(targetAbs, '.conductor-manifest.json');
  let manifest = null;
  if (!fs.existsSync(manifestPath)) {
    add('D1', 'FAIL', `no .conductor-manifest.json in ${targetAbs} — not a CONDUCTOR install (or installed pre-manifest / uninstalled)`);
    return finish();
  }
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  } catch (e) {
    add('D1', 'FAIL', `.conductor-manifest.json does not parse: ${e.message}`);
    return finish();
  }
  if (typeof manifest.version !== 'string' || !Array.isArray(manifest.emitted_files)) {
    add('D1', 'FAIL', `.conductor-manifest.json missing 'version' or 'emitted_files'`);
    return finish();
  }
  if (manifest.emitted_files.length === 0) {
    add('D1', 'FAIL', `.conductor-manifest.json has an empty 'emitted_files' — a real install always tracks files (manifest damaged or hand-edited?)`);
    return finish();
  }
  // Every tracked path must be a non-empty RELATIVE path that stays inside the
  // target — a forged/merge-damaged manifest must not let doctor read (or later
  // checks reason about) files outside the install root.
  const badPaths = [];
  for (const ef of manifest.emitted_files) {
    const p = ef && ef.path;
    if (typeof p !== 'string' || !p.trim() || path.isAbsolute(p)) { badPaths.push(String(p)); continue; }
    const resolved = path.resolve(targetAbs, p);
    if (resolved !== targetAbs && !resolved.startsWith(targetAbs + path.sep)) badPaths.push(p);
  }
  if (badPaths.length) {
    add('D1', 'FAIL', `manifest contains ${badPaths.length} invalid/escaping path(s): ${badPaths.slice(0, 4).join(', ')}${badPaths.length > 4 ? ', …' : ''}`);
    return finish();
  }
  add('D1', 'OK', `manifest valid — ${manifest.emitted_files.length} tracked files, recipes: ${(manifest.recipes_enabled || []).join(', ') || '(none)'}`);

  const adapter = inferAdapter(manifest, targetAbs);
  const meta = adapter ? loadAdapterMetadata(adapter) : null;

  // ---- D2 version drift ------------------------------------------------------
  const pkgVersion = readPkgVersion();
  const installedVersion = String(manifest.version).replace(/^v/, '');
  if (!pkgVersion) {
    add('D2', 'WARN', 'cannot read the running package version');
  } else if (installedVersion === 'unknown' || installedVersion === '') {
    add('D2', 'WARN', `manifest has no usable version stamp ('${manifest.version}')`);
  } else if (installedVersion !== pkgVersion) {
    add('D2', 'WARN', `installed by v${installedVersion}, running CLI is v${pkgVersion} — re-run init to refresh (backups + manifest keep it safe)`);
  } else {
    add('D2', 'OK', `install version matches running CLI (v${pkgVersion})`);
  }

  // ---- D3 file integrity -----------------------------------------------------
  const missing = [];
  for (const ef of manifest.emitted_files) {
    if (!ef || typeof ef.path !== 'string') continue;
    if (!fs.existsSync(path.join(targetAbs, ef.path))) missing.push(ef.path);
  }
  if (missing.length) {
    add('D3', 'FAIL', `${missing.length} manifest-tracked file(s) missing: ${missing.slice(0, 6).join(', ')}${missing.length > 6 ? ', …' : ''}`);
  } else {
    add('D3', 'OK', 'all manifest-tracked files exist');
  }

  // ---- D4 stale legacy paths ---------------------------------------------------
  if (!adapter) {
    add('D4', 'WARN', 'manifest has no adapter field and footprint is ambiguous — skipping legacy-path check');
  } else if (!meta) {
    add('D4', 'WARN', `no metadata for adapter '${adapter}' in this package — skipping legacy-path check`);
  } else {
    const emitted = new Set(manifest.emitted_files.map((e) => e && e.path).filter(Boolean));
    const staleLegacy = (meta.legacy_paths || []).filter((lp) => {
      if (fs.existsSync(path.join(targetAbs, lp)) === false) return false;
      // Intentional legacy emissions are manifest-tracked (e.g. --legacy-cursorrules).
      if (emitted.has(lp) || manifest.legacy_cursorrules === true && lp === '.cursorrules') return false;
      return true;
    });
    if (staleLegacy.length) {
      add('D4', 'WARN', `legacy path(s) present alongside the modern install: ${staleLegacy.join(', ')} — the tool may read both; consider removing after migrating content`);
    } else {
      add('D4', 'OK', `no stale legacy paths (adapter: ${adapter})`);
    }
  }

  // ---- D5 hook validity ---------------------------------------------------------
  let hookProblems = 0, hookChecked = 0;
  let bashAvailable = true;
  for (const ef of manifest.emitted_files) {
    if (!ef || typeof ef.path !== 'string') continue;
    const abs = path.join(targetAbs, ef.path);
    if (!fs.existsSync(abs)) continue; // D3 already reported it
    if (ef.path.endsWith('.json')) {
      hookChecked++;
      try { JSON.parse(fs.readFileSync(abs, 'utf8')); }
      catch (e) { hookProblems++; add('D5', 'FAIL', `${ef.path} is not valid JSON: ${e.message}`); }
    } else if (ef.path.endsWith('.sh')) {
      hookChecked++;
      try { fs.accessSync(abs, fs.constants.X_OK); }
      catch { hookProblems++; add('D5', 'FAIL', `${ef.path} is not executable (chmod +x)`); }
      if (bashAvailable) {
        const r = spawnSync('bash', ['-n', abs], { stdio: 'pipe' });
        if (r.error) { bashAvailable = false; add('D5', 'WARN', 'bash not available — skipping syntax checks'); }
        else if (r.status !== 0) { hookProblems++; add('D5', 'FAIL', `${ef.path} has a bash syntax error`); }
      }
    }
  }
  if (hookProblems === 0) add('D5', 'OK', `hook/config surfaces sane (${hookChecked} .json/.sh file(s) checked)`);

  // ---- D6 doc-link liveness -------------------------------------------------------
  let deadLinks = 0, docsChecked = 0;
  const linkRe = /\[[^\]]*\]\(([^)\s]+)\)/g;
  for (const ef of manifest.emitted_files) {
    if (!ef || typeof ef.path !== 'string' || !ef.path.endsWith('.md')) continue;
    const abs = path.join(targetAbs, ef.path);
    if (!fs.existsSync(abs)) continue;
    docsChecked++;
    const src = fs.readFileSync(abs, 'utf8');
    let m;
    while ((m = linkRe.exec(src)) !== null) {
      const href = m[1];
      if (/^(https?:|mailto:|#)/.test(href)) continue;
      const dest = path.resolve(path.dirname(abs), href.split('#')[0]);
      if (!fs.existsSync(dest)) {
        deadLinks++;
        if (deadLinks <= 5) add('D6', 'WARN', `${ef.path}: dead relative link → ${href}`);
      }
    }
  }
  if (deadLinks === 0) add('D6', 'OK', `relative links resolve in ${docsChecked} emitted doc(s)`);
  else if (deadLinks > 5) add('D6', 'WARN', `…and ${deadLinks - 5} more dead link(s)`);

  // ---- D7 stale claims ---------------------------------------------------------------
  const rules = loadStaleTokens();
  if (!rules.length) {
    add('D7', 'WARN', 'tools/stale-tokens.txt not found in this package — skipping stale-claim scan');
  } else {
    let staleHits = 0;
    for (const ef of manifest.emitted_files) {
      if (!ef || typeof ef.path !== 'string') continue;
      if (!/\.(md|sh|mdc|json|toml)$/.test(ef.path) && !/(^|\/)\.(windsurfrules|cursorrules)$/.test(ef.path)) continue;
      const abs = path.join(targetAbs, ef.path);
      if (!fs.existsSync(abs)) continue;
      const lines = fs.readFileSync(abs, 'utf8').split('\n');
      for (const rule of rules) {
        let allowRe = null;
        if (rule.allow) { try { allowRe = new RegExp(rule.allow); } catch { allowRe = null; } }
        for (const line of lines) {
          if (!line.includes(rule.pattern)) continue;
          if (line.includes('stale-ok:')) continue;
          if (allowRe && allowRe.test(line)) continue;
          staleHits++;
          if (staleHits <= 5) add('D7', 'WARN', `${ef.path}: stale claim '${rule.pattern}' (${rule.reason}) — re-install to refresh`);
          break; // one report per rule per file
        }
      }
    }
    if (staleHits === 0) add('D7', 'OK', 'no known-stale claims in emitted files');
    else if (staleHits > 5) add('D7', 'WARN', `…and ${staleHits - 5} more stale claim(s)`);
  }

  return finish();
}

module.exports = { run };
