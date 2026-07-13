'use strict';

/*
 * omniconductor doctor — read-only health check for an installed project (ADR-041).
 *
 * Anchors on adapter manifests under <target>/.conductor/manifests/ (falling
 * back to the legacy root manifest) and NEVER writes anything.
 * The bash adapters remain the single source of truth for install logic
 * (ADR-002/023/025) — doctor only inspects their output.
 *
 * Check groups:
 *   D1 manifest validity     — exists, parses, has version + emitted_files
 *   D2 version drift         — manifest version vs the running package version
 *   D3 file integrity        — every emitted file exists and still matches its hash
 *   D4 stale legacy paths    — adapter's legacy paths present in the target
 *   D5 hook validity         — emitted .json parse; emitted .sh executable + `bash -n`
 *   D6 doc-link liveness     — relative markdown links in emitted docs resolve
 *   D7 stale claims          — emitted files scanned against tools/stale-tokens.txt
 *   D8 footprint ownership   — tool-native surfaces have matching manifests
 *   D9 Git tracking          — durable runtime files are version-controlled
 *   D10 work-state drift     — CURRENT_WORK branch/base/head vs real Git state
 *   D11 model routing        — saved Tier mappings, adapter coverage, enforcement truth
 *
 * Severity: FAIL = broken install · WARN = degraded/attention · OK.
 * Exit codes: 0 = all OK · 1 = warnings only · 2 = failures (or unusable target).
 */

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const modelRouting = require('./model-routing.js');
const pathSafety = require('./path-safety.js');

const ROOT = path.resolve(__dirname, '..');

function readPkgVersion() {
  try { return JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')).version || null; }
  catch { return null; }
}

function versionAtLeast(value, major, minor) {
  const match = String(value || '').replace(/^v/, '').match(/^(\d+)\.(\d+)/);
  return !!match && (Number(match[1]) > major || (Number(match[1]) === major && Number(match[2]) >= minor));
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

function sha256Buffer(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function sha256File(file) {
  return sha256Buffer(fs.readFileSync(file));
}

function discoverManifestPaths(targetAbs) {
  const dir = path.join(targetAbs, '.conductor', 'manifests');
  if (fs.existsSync(dir) && fs.statSync(dir).isDirectory()) {
    const scoped = fs.readdirSync(dir)
      .filter((name) => name.endsWith('.json'))
      .sort()
      .map((name) => path.join(dir, name));
    if (scoped.length) return scoped;
  }
  const legacy = path.join(targetAbs, '.conductor-manifest.json');
  return fs.existsSync(legacy) ? [legacy] : [];
}

const ROLE_TIERS = {
  planner: 1,
  reviewer: 1,
  'code-reviewer': 1,
  builder: 1,
  helper: 2,
  designer: 2,
  scribe: 2,
  utility: 3,
  reflector: 1,
};

function rolePath(tool, role) {
  if (tool === 'windsurf' && role === 'reflector') return '.devin/rules/reflector.md';
  const paths = {
    claude: `.claude/agents/${role}.md`,
    cursor: `.cursor/agents/${role}.md`,
    copilot: `.github/agents/${role}.agent.md`,
    gemini: `.gemini/agents/${role}.md`,
    codex: `.codex/agents/${role}.toml`,
    windsurf: `.windsurf/workflows/${role}.md`,
  };
  return paths[tool];
}

function frontmatterField(source, key) {
  const lines = String(source).split(/\r?\n/);
  if (lines[0] !== '---') return { present: false, value: '' };
  for (let index = 1; index < lines.length && lines[index] !== '---'; index++) {
    const match = lines[index].match(new RegExp(`^${key}:[ \\t]*(.*)$`));
    if (!match) continue;
    return { present: true, value: match[1].trim().replace(/^(?:"([\s\S]*)"|'([\s\S]*)')$/, '$1$2') };
  }
  return { present: false, value: '' };
}

function tomlStringField(source, key) {
  const match = String(source).match(new RegExp(`^${key}[ \\t]*=[ \\t]*"([^"]*)"[ \\t]*$`, 'm'));
  return { present: !!match, value: match ? match[1] : '' };
}

function routingOutputProblems(targetAbs, manifestSources, routing, tools) {
  const problems = [];
  const efforts = { 1: 'high', 2: 'medium', 3: 'low' };
  for (const tool of tools) {
    const source = manifestSources.find(({ adapter }) => adapter === tool);
    if (!source) continue;
    const managed = new Set(source.manifest.emitted_files.map((entry) => entry && entry.path).filter(Boolean));
    const emitsRoles = Object.keys(ROLE_TIERS).some((role) => managed.has(rolePath(tool, role)));
    if (!emitsRoles) continue;
    for (const [role, tier] of Object.entries(ROLE_TIERS)) {
      const rel = rolePath(tool, role);
      const abs = path.join(targetAbs, rel);
      if (!managed.has(rel)) {
        if (role !== 'reflector' && ['full', 'strict'].includes(source.manifest.mode)) {
          problems.push(`${tool}:${role} role is absent from managed output`);
        }
        continue;
      }
      if (!fs.existsSync(abs)) {
        problems.push(`${tool}:${role} role is absent from managed output`);
        continue;
      }
      const contents = fs.readFileSync(abs, 'utf8');
      if (tool === 'windsurf') {
        const model = frontmatterField(contents, 'model');
        if (model.present) problems.push(`${tool}:${role} declares unsupported workflow-local model '${model.value}'`);
        if (!contents.includes('select **Adaptive**')) problems.push(`${tool}:${role} is missing the Adaptive session preflight`);
        continue;
      }
      const model = tool === 'codex' ? tomlStringField(contents, 'model') : frontmatterField(contents, 'model');
      const expected = routing.adapters[tool].tiers[String(tier)].resolved;
      if (!model.present || model.value !== expected) {
        problems.push(`${tool}:${role} model '${model.present ? model.value : '(missing)'}' != saved Tier ${tier} '${expected}'`);
      }
      if (tool === 'codex') {
        const effort = tomlStringField(contents, 'model_reasoning_effort');
        if (!effort.present || effort.value !== efforts[tier]) {
          problems.push(`${tool}:${role} reasoning effort '${effort.present ? effort.value : '(missing)'}' != Tier ${tier} '${efforts[tier]}'`);
        }
      }
    }
  }
  return problems;
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
  const manifestPaths = discoverManifestPaths(targetAbs);
  if (!manifestPaths.length) {
    add('D1', 'FAIL', `no adapter manifest in ${targetAbs} — not a CONDUCTOR install (or already uninstalled)`);
    return finish();
  }
  const manifestSources = [];
  const badPaths = [];
  const seenAdapters = new Set();
  for (const manifestPath of manifestPaths) {
    let manifest;
    const authoritative = manifestPath.includes(`${path.sep}.conductor${path.sep}manifests${path.sep}`);
    try {
      manifest = authoritative
        ? pathSafety.validateManifest(manifestPath, targetAbs, path.basename(manifestPath, '.json'))
        : JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    }
    catch (e) {
      add('D1', 'FAIL', `${path.relative(targetAbs, manifestPath)} is unsafe or invalid: ${e.message}`);
      return finish();
    }
    if (typeof manifest.version !== 'string' || !Array.isArray(manifest.emitted_files) || manifest.emitted_files.length === 0) {
      add('D1', 'FAIL', `${path.relative(targetAbs, manifestPath)} missing usable version/emitted_files`);
      return finish();
    }
    const adapter = inferAdapter(manifest, targetAbs);
    if (!adapter) {
      add('D1', 'FAIL', `${path.relative(targetAbs, manifestPath)} has no identifiable adapter`);
      return finish();
    }
    if (seenAdapters.has(adapter)) {
      add('D1', 'FAIL', `duplicate authoritative manifest for adapter '${adapter}'`);
      return finish();
    }
    seenAdapters.add(adapter);
    if (authoritative) {
      if (path.basename(manifestPath, '.json') !== adapter) {
        add('D1', 'FAIL', `${path.relative(targetAbs, manifestPath)} declares adapter '${adapter}'`);
        return finish();
      }
      if (manifest.schema_version !== 2 || manifest.manifest_scope !== 'adapter') {
        add('D1', 'FAIL', `${path.relative(targetAbs, manifestPath)} is not an adapter-scoped schema-v2 manifest`);
        return finish();
      }
    }
    const localPaths = new Set();
    for (const ef of manifest.emitted_files) {
      const p = ef && ef.path;
      if (typeof p !== 'string' || !p.trim() || path.isAbsolute(p)) { badPaths.push(String(p)); continue; }
      const resolved = path.resolve(targetAbs, p);
      if (resolved !== targetAbs && !resolved.startsWith(targetAbs + path.sep)) badPaths.push(p);
      if (localPaths.has(`${p}#${ef.type === 'block' ? ef.block || '' : ''}`)) {
        add('D1', 'FAIL', `${path.relative(targetAbs, manifestPath)} contains duplicate ownership for ${p}`);
        return finish();
      }
      localPaths.add(`${p}#${ef.type === 'block' ? ef.block || '' : ''}`);
    }
    manifestSources.push({ manifest, manifestPath, adapter, meta: loadAdapterMetadata(adapter) });
  }
  if (badPaths.length) {
    add('D1', 'FAIL', `manifest contains ${badPaths.length} invalid/escaping path(s): ${badPaths.slice(0, 4).join(', ')}${badPaths.length > 4 ? ', …' : ''}`);
    return finish();
  }
  const manifest = {
    emitted_files: manifestSources.flatMap(({ manifest: m, adapter, manifestPath }) =>
      m.emitted_files.map((ef) => ({ ...ef, _adapter: adapter, _manifestPath: manifestPath }))),
  };
  const sharedHashes = new Map();
  for (const ef of manifest.emitted_files) {
    if (!ef.path || !ef.sha256 || ef.type === 'block') continue;
    if (!sharedHashes.has(ef.path)) sharedHashes.set(ef.path, new Set());
    sharedHashes.get(ef.path).add(ef.sha256);
  }
  const conflicts = [...sharedHashes.entries()].filter(([, hashes]) => hashes.size > 1).map(([p]) => p);
  if (conflicts.length) {
    add('D1', 'FAIL', `cross-adapter ownership has conflicting checksums: ${conflicts.slice(0, 6).join(', ')}`);
    return finish();
  }
  add('D1', 'OK', `${manifestSources.length} adapter manifest(s) valid — ${[...seenAdapters].join(', ')}; ${manifest.emitted_files.length} tracked entries`);

  // ---- D2 version drift ------------------------------------------------------
  const pkgVersion = readPkgVersion();
  if (!pkgVersion) {
    add('D2', 'WARN', 'cannot read the running package version');
  } else {
    const drifted = manifestSources.filter(({ manifest: m }) => String(m.version).replace(/^v/, '') !== pkgVersion);
    if (drifted.length) {
      add('D2', 'WARN', `${drifted.map(({ adapter, manifest: m }) => `${adapter}=v${String(m.version).replace(/^v/, '')}`).join(', ')}; running CLI is v${pkgVersion}`);
    } else add('D2', 'OK', `all ${manifestSources.length} install(s) match running CLI (v${pkgVersion})`);
  }

  // ---- D3 file integrity -----------------------------------------------------
  const missing = [], changed = [];
  for (const ef of manifest.emitted_files) {
    if (!ef || typeof ef.path !== 'string') continue;
    const abs = path.join(targetAbs, ef.path);
    if (!fs.existsSync(abs)) { missing.push(`${ef._adapter}:${ef.path}`); continue; }
    if (ef.sha256 && ef.type !== 'block' && fs.statSync(abs).isFile() && sha256File(abs) !== ef.sha256) {
      changed.push(`${ef._adapter}:${ef.path}`);
    }
    if (ef.type === 'block' && ef.block && ef.sha256) {
      const open = `<!-- conductor:block ${ef.block} -->`;
      const close = `<!-- /conductor:block ${ef.block} -->`;
      const lines = fs.readFileSync(abs, 'utf8').split(/\r?\n/);
      let inside = false, found = false, body = '';
      for (const line of lines) {
        if (line === open) { inside = true; found = true; continue; }
        if (line === close) { inside = false; break; }
        if (inside) body += `${line}\n`;
      }
      if (!found || sha256Buffer(body) !== ef.sha256) changed.push(`${ef._adapter}:${ef.path}#${ef.block}`);
    }
  }
  if (missing.length) {
    add('D3', 'FAIL', `${missing.length} manifest-tracked file(s) missing: ${missing.slice(0, 6).join(', ')}${missing.length > 6 ? ', …' : ''}`);
  } else {
    add('D3', 'OK', 'all manifest-tracked files exist');
  }
  if (changed.length) add('D3', 'WARN', `${changed.length} managed file/block(s) customized since install: ${changed.slice(0, 6).join(', ')}${changed.length > 6 ? ', …' : ''}`);
  else add('D3', 'OK', 'all managed checksums match');

  // ---- D4 stale legacy paths ---------------------------------------------------
  for (const source of manifestSources) {
    const { adapter, meta } = source;
    if (!meta) {
      add('D4', 'WARN', `no metadata for adapter '${adapter}' — skipping legacy-path check`);
      continue;
    }
    const emitted = new Set(source.manifest.emitted_files.map((e) => e && e.path).filter(Boolean));
    const staleLegacy = (meta.legacy_paths || []).filter((lp) => {
      if (fs.existsSync(path.join(targetAbs, lp)) === false) return false;
      if (emitted.has(lp) || source.manifest.legacy_cursorrules === true && lp === '.cursorrules') return false;
      return true;
    });
    if (staleLegacy.length) {
      add('D4', 'WARN', `legacy path(s) present alongside the modern install: ${staleLegacy.join(', ')} — the tool may read both; consider removing after migrating content`);
    } else add('D4', 'OK', `no stale legacy paths (adapter: ${adapter})`);
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
    if (/\.(json|sh|toml)$/.test(ef.path)) {
      const src = fs.readFileSync(abs, 'utf8');
      if (src.includes('.Codex/')) {
        hookProblems++; add('D5', 'FAIL', `${ef.path} contains case-drifting '.Codex/' (must be '.codex/')`);
      }
      if (/\/(Users|home)\/[^/$"' ]+\//.test(src)) {
        hookProblems++; add('D5', 'FAIL', `${ef.path} contains a user-specific absolute path`);
      }
      if (ef._adapter === 'codex' && /"permissionDecision"\s*:\s*"ask"/.test(src)
          && !/^export CONDUCTOR_HOOK_DIALECT=codex$/m.test(src)) {
        hookProblems++; add('D5', 'FAIL', `${ef.path} returns unsupported Codex permissionDecision 'ask'`);
      }
      if (ef._adapter === 'codex' && /^\.codex\/hooks\//.test(ef.path)
          && /tool_name.{0,80}(Agent|Read)/s.test(src)) {
        hookProblems++; add('D5', 'FAIL', `${ef.path} contains a Claude tool matcher in the Codex runtime`);
      }
      if (ef._adapter === 'codex' && /^\.codex\/agents\/[A-Za-z0-9_-]+\.toml$/.test(ef.path)) {
        const role = path.basename(ef.path, '.toml');
        const openToken = 'developer_instructions = """';
        const openAt = src.indexOf(openToken);
        const closeAt = openAt >= 0 ? src.indexOf('\n"""', openAt + openToken.length) : -1;
        const header = openAt >= 0 ? src.slice(0, openAt).trim().split(/\r?\n/) : [];
        const tail = closeAt >= 0 ? src.slice(closeAt + 4).trim() : 'invalid';
        const fields = new Map();
        let invalidToml = openAt < 0 || closeAt < 0 || tail.length > 0;
        for (const line of header) {
          const m = line.match(/^([A-Za-z_]+) = "([^"]+)"$/);
          if (!m || fields.has(m[1])) { invalidToml = true; continue; }
          fields.set(m[1], m[2]);
        }
        const allowed = new Set(['name', 'description', 'model', 'model_reasoning_effort', 'sandbox_mode']);
        if ([...fields.keys()].some((k) => !allowed.has(k))) invalidToml = true;
        const expectedSandbox = ['planner', 'reviewer', 'code-reviewer'].includes(role) ? 'read-only' : 'workspace-write';
        if (fields.get('name') !== role || !fields.get('description')
            || !['low', 'medium', 'high'].includes(fields.get('model_reasoning_effort'))
            || fields.get('sandbox_mode') !== expectedSandbox
            || (fields.has('model') && !/^[A-Za-z0-9._-]+$/.test(fields.get('model')))) invalidToml = true;
        if (invalidToml) {
          hookProblems++; add('D5', 'FAIL', `${ef.path} has an invalid Codex agent TOML contract or role sandbox`);
        }
      }
      const refs = [...src.matchAll(/(?:\.claude|\.cursor|\.codex|\.windsurf|\.conductor|\.github|\.gemini)\/[A-Za-z0-9_./-]+\.sh/g)]
        .map((m) => m[0]);
      for (const ref of new Set(refs)) {
        if (!fs.existsSync(path.join(targetAbs, ref))) {
          hookProblems++; add('D5', 'FAIL', `${ef.path} references missing hook script ${ref}`);
        }
      }
    }
  }
  const requiresProfile = manifestSources.some(({ manifest: m }) => ['full', 'minimal', 'strict'].includes(m.mode));
  const profilePath = path.join(targetAbs, '.conductor', 'project.json');
  if (requiresProfile) {
    try {
      const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
      if (profile.schema_version !== 1 || typeof profile.current_work_path !== 'string'
          || !Array.isArray(profile.source_extensions) || !profile.source_extensions.length
          || !Array.isArray(profile.spec_paths) || !profile.thresholds) {
        throw new Error('missing schema/current_work/source_extensions/spec_paths/thresholds');
      }
    } catch (e) {
      hookProblems++; add('D5', 'FAIL', `.conductor/project.json is missing or invalid: ${e.message}`);
    }
  }
  const codexSource = manifestSources.find(({ adapter }) => adapter === 'codex');
  if (codexSource && ['full', 'minimal', 'strict'].includes(codexSource.manifest.mode)) {
    const agentsPath = path.join(targetAbs, 'AGENTS.md');
    if (fs.existsSync(agentsPath)) {
      const agents = fs.readFileSync(agentsPath, 'utf8');
      const bytes = Buffer.byteLength(agents, 'utf8');
      if (bytes > 32768) {
        hookProblems++;
        add('D5', 'FAIL', `AGENTS.md is ${bytes} bytes and exceeds Codex's default 32768-byte project-instruction budget; trailing rules may be truncated`);
      } else if (!agents.includes('CONDUCTOR_KERNEL_END')) {
        hookProblems++;
        add('D5', 'FAIL', 'AGENTS.md is not the bounded CONDUCTOR kernel — reinstall the Codex adapter to prevent silent instruction truncation');
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

  // ---- D8 native footprint ownership -------------------------------------------
  const footprints = {
    claude: ['.claude/rules', 'CLAUDE.md'],
    cursor: ['.cursor/rules'],
    copilot: ['.github/copilot-instructions.md', '.github/instructions'],
    gemini: ['GEMINI.md', '.gemini/styleguide.md'],
    codex: ['.codex/hooks.json', '.codex/agents'],
    windsurf: ['.windsurfrules', '.devin/rules'],
  };
  let unowned = 0;
  for (const [tool, paths] of Object.entries(footprints)) {
    const present = paths.some((p) => fs.existsSync(path.join(targetAbs, p)));
    if (present && !seenAdapters.has(tool)) {
      unowned++;
      add('D8', 'WARN', `${tool} footprint exists without an authoritative ${tool} manifest — run init --target=${tool}`);
    }
  }
  if (!unowned) add('D8', 'OK', 'every detected tool footprint has a matching adapter manifest');
  const projectionPath = path.join(targetAbs, '.conductor-manifest.json');
  if (fs.existsSync(projectionPath)) {
    try {
      const projection = JSON.parse(fs.readFileSync(projectionPath, 'utf8'));
      const projected = new Set(Array.isArray(projection.installed_adapters) ? projection.installed_adapters : []);
      const mismatched = projection.manifest_scope !== 'projection' || projected.size !== seenAdapters.size
        || [...seenAdapters].some((a) => !projected.has(a));
      if (mismatched) add('D8', 'FAIL', 'root compatibility manifest does not match authoritative adapter manifests');
      else add('D8', 'OK', 'root compatibility manifest accurately projects all installed adapters');
    } catch (e) {
      add('D8', 'FAIL', `root compatibility manifest is invalid JSON: ${e.message}`);
    }
  } else add('D8', 'WARN', 'root compatibility manifest is missing');

  // ---- D9 durable files should be tracked in Git -------------------------------
  const inGit = spawnSync('git', ['-C', targetAbs, 'rev-parse', '--is-inside-work-tree'], { encoding: 'utf8' });
  if (inGit.status !== 0 || String(inGit.stdout).trim() !== 'true') {
    add('D9', 'OK', 'target is not a Git worktree — tracking check not applicable');
  } else {
    const durable = [...new Set(manifest.emitted_files
      .map((ef) => ef && ef.path)
      .filter((p) => p && (/^(AGENTS|CLAUDE|GEMINI)\.md$/.test(p)
        || /^\.(claude|cursor|codex|gemini|github|windsurf|devin)\//.test(p)
        || p === '.windsurfrules' || p === '.conductor/project.json'))
      .concat(manifestPaths.map((p) => path.relative(targetAbs, p)), ['.conductor-manifest.json', '.conductor/model-routing.json']))];
    const notTracked = durable.filter((p) => spawnSync('git', ['-C', targetAbs, 'ls-files', '--error-unmatch', '--', p], { stdio: 'ignore' }).status !== 0);
    if (notTracked.length) add('D9', 'WARN', `${notTracked.length} durable runtime file(s) are not Git-tracked: ${notTracked.slice(0, 6).join(', ')}${notTracked.length > 6 ? ', …' : ''}`);
    else add('D9', 'OK', `${durable.length} durable runtime file(s) are Git-tracked`);
  }

  // ---- D10 CURRENT_WORK structured Git-state drift -----------------------------
  let currentWorkRel = 'docs/CURRENT_WORK.md';
  try {
    const profile = JSON.parse(fs.readFileSync(path.join(targetAbs, '.conductor', 'project.json'), 'utf8'));
    if (typeof profile.current_work_path === 'string' && profile.current_work_path) currentWorkRel = profile.current_work_path;
  } catch { /* D5 reports an invalid required profile. */ }
  const currentWork = path.join(targetAbs, currentWorkRel);
  if (!fs.existsSync(currentWork) || inGit.status !== 0) {
    add('D10', 'OK', 'structured work-state check not applicable');
  } else {
    const src = fs.readFileSync(currentWork, 'utf8');
    const field = (name) => {
      const m = src.match(new RegExp(`^[-*]?[ \\t]*(?:\\*\\*)?${name}(?:\\*\\*)?[ \\t]*:[ \\t]*(?:\\x60)?([^\\x60\\n]+)`, 'im'));
      return m ? m[1].trim() : '';
    };
    const placeholder = (v) => !v || /^(<|\(|unknown|unset|none|todo|auto)/i.test(v);
    const branch = field('active_branch') || field('Active branch');
    const base = field('base_sha') || field('Base SHA');
    const head = field('last_verified_head') || field('Last verified HEAD');
    const realBranch = String(spawnSync('git', ['-C', targetAbs, 'branch', '--show-current'], { encoding: 'utf8' }).stdout || '').trim();
    const realHead = String(spawnSync('git', ['-C', targetAbs, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout || '').trim();
    let drift = 0;
    if (!placeholder(branch) && branch !== realBranch) { drift++; add('D10', 'FAIL', `CURRENT_WORK active_branch='${branch}', Git branch='${realBranch}'`); }
    if (!placeholder(base)) {
      const ancestor = spawnSync('git', ['-C', targetAbs, 'merge-base', '--is-ancestor', base, 'HEAD'], { stdio: 'ignore' });
      if (ancestor.status !== 0) { drift++; add('D10', 'FAIL', `CURRENT_WORK base_sha '${base}' is not an ancestor of HEAD`); }
    }
    if (!placeholder(head) && realHead && !realHead.startsWith(head) && !head.startsWith(realHead)) {
      drift++; add('D10', 'WARN', `CURRENT_WORK last_verified_head='${head}', current HEAD='${realHead.slice(0, 12)}'`);
    }
    if (!drift) add('D10', 'OK', 'CURRENT_WORK structured Git state matches the worktree (or fields are placeholders)');
  }

  // ---- D11 project model-routing state --------------------------------------
  if (fs.existsSync(path.join(targetAbs, '.conductor', 'model-routing-transaction.json'))) {
    add('D11', 'FAIL', 'an interrupted model-routing transaction needs recovery; rerun `omniconductor models configure` before dispatching roles');
    return finish();
  }
  const routingRequired = manifestSources
    .filter(({ adapter, manifest: installed }) => {
      const managed = new Set(installed.emitted_files.map((entry) => entry && entry.path).filter(Boolean));
      return Object.keys(ROLE_TIERS).some((role) => managed.has(rolePath(adapter, role)));
    })
    .map(({ adapter }) => adapter);
  if (!routingRequired.length) {
    add('D11', 'OK', 'no managed role output requires model routing');
  } else {
    let routing;
    try { routing = modelRouting.loadConfig(targetAbs); }
    catch (error) { add('D11', 'FAIL', error.message); return finish(); }
    if (!routing) {
      const requiresConfig = manifestSources.some(({ adapter, manifest: installed }) => {
        const managed = new Set(installed.emitted_files.map((entry) => entry && entry.path).filter(Boolean));
        return versionAtLeast(installed.version, 1, 1)
          && Object.keys(ROLE_TIERS).some((role) => managed.has(rolePath(adapter, role)));
      });
      add('D11', requiresConfig ? 'FAIL' : 'WARN', `.conductor/model-routing.json is missing (${requiresConfig ? 'v1.1+ install is incomplete or bypassed' : 'manual adapter install or pre-1.1 upgrade'}) — role dispatch must pause until omniconductor models configure is run`);
    } else {
      const missing = modelRouting.missingTargets(routing, routingRequired);
      if (missing.length) {
        add('D11', 'FAIL', `model routing is missing or invalid for installed adapter(s): ${missing.join(', ')}`);
      } else {
        const advisory = [];
        const syntaxOnly = [];
        const parameterBaseOnly = [];
        for (const tool of routingRequired) {
          const entry = routing.adapters[tool];
          if (entry.enforcement === 'advisory-session') advisory.push(tool);
          if (Object.values(entry.tiers).some((tier) => tier.validation === 'syntax-only')) syntaxOnly.push(tool);
          if (Object.values(entry.tiers).some((tier) => tier.validation === 'catalog-base-verified')) parameterBaseOnly.push(tool);
        }
        const outputProblems = routingOutputProblems(targetAbs, manifestSources, routing, routingRequired);
        if (outputProblems.length) {
          add('D11', 'FAIL', `saved mappings disagree with managed role output: ${outputProblems.slice(0, 8).join('; ')}${outputProblems.length > 8 ? '; …' : ''}`);
        } else {
          add('D11', 'OK', `saved Tier 1/2/3 mappings match managed role output for ${routingRequired.length} installed adapter(s), revision ${routing.config_revision}`);
        }
        if (syntaxOnly.length) add('D11', 'WARN', `provider catalog could not be verified for: ${syntaxOnly.join(', ')}; syntax is valid but account/plan availability remains provider-controlled`);
        if (parameterBaseOnly.length) add('D11', 'WARN', `${parameterBaseOnly.join(', ')} base model is catalog-verified; parameter-block availability remains provider-controlled`);
        if (advisory.length) add('D11', 'WARN', `${advisory.join(', ')} routing is advisory-session; confirm Adaptive in the tool UI`);
      }
    }
  }

  return finish();
}

module.exports = { run };
