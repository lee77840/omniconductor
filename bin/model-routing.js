'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const pathSafety = require('./path-safety.js');

const SCHEMA_VERSION = 1;
const CONFIG_REL = path.join('.conductor', 'model-routing.json');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
const TIER_LABELS = {
  1: 'conceptual / complex',
  2: 'routine',
  3: 'trivial',
};
const RECOMMENDED = {
  claude: { 1: 'opus', 2: 'sonnet', 3: 'haiku' },
  cursor: { 1: 'gpt-5.6-sol', 2: 'gpt-5.6-terra', 3: 'gpt-5.6-luna' },
  copilot: { 1: 'gpt-5.6-sol', 2: 'gpt-5.6-terra', 3: 'gpt-5.6-luna' },
  gemini: { 1: 'pro', 2: 'flash', 3: 'flash-lite' },
  codex: { 1: 'gpt-5.6-sol', 2: 'gpt-5.6-terra', 3: 'gpt-5.6-luna' },
  windsurf: { 1: 'adaptive', 2: 'adaptive', 3: 'adaptive' },
};
const ENFORCEMENT = {
  claude: 'native-agent-model',
  cursor: 'native-agent-model-with-provider-fallback-risk',
  copilot: 'native-agent-model-with-provider-policy-risk',
  gemini: 'native-agent-model',
  codex: 'native-agent-model-and-reasoning-effort',
  windsurf: 'advisory-session',
};
const LOCK_STALE_MS = 30_000;
const TRANSACTION_REL = path.join('.conductor', 'model-routing-transaction.json');
const ROLE_DIRS = {
  claude: ['.claude/agents', '.md'],
  cursor: ['.cursor/agents', '.md'],
  copilot: ['.github/agents', '.agent.md'],
  gemini: ['.gemini/agents', '.md'],
  codex: ['.codex/agents', '.toml'],
  windsurf: ['.windsurf/workflows', '.md'],
};

function configPath(targetAbs) {
  return path.join(targetAbs, CONFIG_REL);
}

function assertSafeTargetFile(file) {
  if (!fs.existsSync(file)) return;
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error(`${CONFIG_REL} must be a regular file, not a link or special file`);
  }
  if (stat.nlink !== 1) throw new Error(`${CONFIG_REL} must not be hard-linked`);
}

function validateModel(tool, value) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 160) {
    return 'must be a non-empty string of at most 160 characters';
  }
  if (/[\u0000-\u0020\u007f]/.test(value)) return 'must not contain whitespace or control characters';
  if (tool === 'windsurf') {
    return value === 'adaptive' ? null : "must be 'adaptive' because Windsurf workflows cannot pin a model";
  }
  const basic = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
  const cursor = /^[A-Za-z0-9][A-Za-z0-9._:/-]*(?:\[[A-Za-z0-9._:=,-]+\])?$/;
  if (!(tool === 'cursor' ? cursor : basic).test(value)) {
    return tool === 'cursor'
      ? 'contains unsupported characters (Cursor allows an optional [key=value] parameter block)'
      : 'contains unsupported model-ID characters';
  }
  return null;
}

function cursorBaseModel(value) {
  return String(value).replace(/\[[^\]]+\]$/, '');
}

function expectedTierMetadata(tool, model) {
  if (tool === 'windsurf') return { mode: 'adaptive-session', validation: ['advisory-session'] };
  if (tool === 'claude' && ['opus', 'sonnet', 'haiku'].includes(model)) {
    return { mode: 'family-alias', validation: ['family-alias'] };
  }
  if (tool === 'gemini' && ['pro', 'flash', 'flash-lite'].includes(model)) {
    return { mode: 'semantic-alias', validation: ['semantic-alias'] };
  }
  const validation = tool === 'codex'
    ? ['syntax-only', 'binary-catalog-verified']
    : ['syntax-only', 'catalog-verified'];
  if (tool === 'cursor' && cursorBaseModel(model) !== model) validation.push('catalog-base-verified');
  return { mode: 'exact', validation };
}

function validateAdapterEntry(tool, entry) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return `${tool}: missing adapter object`;
  if (entry.enforcement !== ENFORCEMENT[tool]) {
    return `${tool}: enforcement must be '${ENFORCEMENT[tool]}'`;
  }
  if (!entry.tiers || typeof entry.tiers !== 'object') return `${tool}: missing tiers`;
  for (const tier of [1, 2, 3]) {
    const item = entry.tiers[String(tier)];
    if (!item || typeof item !== 'object') return `${tool}: missing Tier ${tier}`;
    const error = validateModel(tool, item.resolved);
    if (error) return `${tool} Tier ${tier}: ${error}`;
    if (item.requested !== item.resolved) return `${tool} Tier ${tier}: requested/resolved must match (silent fallback is forbidden)`;
    const expected = expectedTierMetadata(tool, item.resolved);
    if (item.mode !== expected.mode) return `${tool} Tier ${tier}: mode must be '${expected.mode}'`;
    if (!expected.validation.includes(item.validation)) {
      return `${tool} Tier ${tier}: validation '${String(item.validation)}' is incompatible with ${expected.mode}`;
    }
    if (typeof item.validated_at !== 'string' || Number.isNaN(Date.parse(item.validated_at))) {
      return `${tool} Tier ${tier}: validated_at must be an ISO timestamp`;
    }
  }
  return null;
}

function validateConfig(config) {
  if (!config || typeof config !== 'object' || Array.isArray(config)) return 'root must be an object';
  if (config.schema_version !== SCHEMA_VERSION) return `unsupported schema_version ${String(config.schema_version)}`;
  if (!Number.isInteger(config.config_revision) || config.config_revision < 1) return 'config_revision must be a positive integer';
  if (!config.adapters || typeof config.adapters !== 'object') return 'adapters object is missing';
  for (const [tool, entry] of Object.entries(config.adapters)) {
    if (!TOOLS.includes(tool)) return `unknown adapter '${tool}'`;
    const error = validateAdapterEntry(tool, entry);
    if (error) return error;
  }
  return null;
}

function loadConfig(targetAbs, options = {}) {
  const file = configPath(targetAbs);
  if (!fs.existsSync(file)) return null;
  assertSafeTargetFile(file);
  let config;
  try { config = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { throw new Error(`${CONFIG_REL} is invalid JSON: ${error.message}`); }
  const problem = validateConfig(config);
  if (problem && !options.allowInvalid) throw new Error(`${CONFIG_REL} is invalid: ${problem}`);
  return config;
}

function safeExecutable(command, targetAbs) {
  const pathValue = process.env.PATH || '';
  for (const dir of pathValue.split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.resolve(dir, command);
    try {
      const stat = fs.statSync(candidate);
      fs.accessSync(candidate, fs.constants.X_OK);
      if (!stat.isFile()) continue;
      if (candidate === targetAbs || candidate.startsWith(targetAbs + path.sep)) return null;
      return candidate;
    } catch { /* continue */ }
  }
  return null;
}

function modelCatalog(tool, targetAbs) {
  if (tool === 'codex') {
    const executable = safeExecutable('codex', targetAbs);
    if (!executable) return null;
    const result = spawnSync(executable, ['debug', 'models', '--bundled'], {
      cwd: targetAbs, encoding: 'utf8', timeout: 8000,
      env: { ...process.env, NO_COLOR: '1' },
    });
    if (result.status !== 0) return null;
    try {
      const parsed = JSON.parse(result.stdout);
      return new Set((parsed.models || []).map((item) => item && item.slug).filter(Boolean));
    } catch { return null; }
  }
  if (tool === 'cursor') {
    const executable = safeExecutable('agent', targetAbs) || safeExecutable('cursor-agent', targetAbs);
    if (!executable) return null;
    const result = spawnSync(executable, ['models'], {
      cwd: targetAbs, encoding: 'utf8', timeout: 8000,
      env: { ...process.env, NO_COLOR: '1' },
    });
    if (result.status !== 0) return null;
    const values = new Set();
    for (const line of String(result.stdout).split(/\r?\n/)) {
      for (const token of line.match(/[A-Za-z0-9][A-Za-z0-9._:/-]*(?:\[[A-Za-z0-9._:=,-]+\])?/g) || []) {
        if (token.includes('-') || token.includes('/') || token === 'auto' || token === 'inherit') values.add(token);
      }
    }
    return values.size ? values : null;
  }
  return null;
}

function validationFor(tool, model, catalog) {
  if (tool === 'windsurf') return 'advisory-session';
  if (tool === 'claude' && ['opus', 'sonnet', 'haiku'].includes(model)) return 'family-alias';
  if (tool === 'gemini' && ['pro', 'flash', 'flash-lite'].includes(model)) return 'semantic-alias';
  if (catalog) {
    if (catalog.has(model)) return tool === 'codex' ? 'binary-catalog-verified' : 'catalog-verified';
    if (tool === 'cursor' && cursorBaseModel(model) !== model && catalog.has(cursorBaseModel(model))) {
      return 'catalog-base-verified';
    }
    return 'catalog-unavailable';
  }
  return 'syntax-only';
}

function buildAdapter(tool, choices, targetAbs, now) {
  const catalog = modelCatalog(tool, targetAbs);
  const tiers = {};
  for (const tier of [1, 2, 3]) {
    const resolved = choices[tier];
    const error = validateModel(tool, resolved);
    if (error) throw new Error(`${tool} Tier ${tier} ${error}: '${resolved}'`);
    const validation = validationFor(tool, resolved, catalog);
    if (validation === 'catalog-unavailable') {
      const catalogLabel = tool === 'codex' ? 'local Codex binary catalog' : 'local provider/account catalog';
      throw new Error(`${tool} Tier ${tier} model '${resolved}' is not present in the ${catalogLabel}; choose another model`);
    }
    const metadata = expectedTierMetadata(tool, resolved);
    tiers[String(tier)] = {
      mode: metadata.mode,
      requested: resolved,
      resolved,
      validation,
      validated_at: now,
    };
  }
  return { enforcement: ENFORCEMENT[tool], tiers };
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function processIsAlive(pid) {
  if (!Number.isInteger(pid) || pid < 1) return false;
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code === 'EPERM'; }
}

function reclaimStaleLock(lock) {
  let stat;
  try { stat = fs.lstatSync(lock); } catch { return false; }
  if (!stat.isDirectory() || stat.isSymbolicLink()) return false;
  let names;
  try { names = fs.readdirSync(lock); } catch { return false; }
  if (names.some((name) => name !== 'owner.json')) return false;
  let owner = null;
  try { owner = JSON.parse(fs.readFileSync(path.join(lock, 'owner.json'), 'utf8')); } catch { /* use directory age */ }
  const created = owner && typeof owner.created_at === 'string' ? Date.parse(owner.created_at) : stat.mtimeMs;
  if (!Number.isFinite(created) || Date.now() - created < LOCK_STALE_MS) return false;
  if (owner && processIsAlive(owner.pid)) return false;

  const tombstone = `${lock}.stale.${process.pid}.${Date.now()}`;
  try { fs.renameSync(lock, tombstone); } catch { return false; }
  try {
    try { fs.unlinkSync(path.join(tombstone, 'owner.json')); } catch { /* absent/malformed lock */ }
    fs.rmdirSync(tombstone);
  } catch {
    // The renamed lock no longer blocks configuration. Unexpected contents were
    // excluded above, so a cleanup failure is harmless and visible on disk.
  }
  return true;
}

function acquireLock(targetAbs) {
  const lock = path.join(targetAbs, '.conductor', 'model-routing.lock');
  fs.mkdirSync(path.dirname(lock), { recursive: true });
  const deadline = Date.now() + 5000;
  while (true) {
    try {
      fs.mkdirSync(lock, { mode: 0o700 });
      const nonce = crypto.randomBytes(16).toString('hex');
      fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ pid: process.pid, nonce, created_at: new Date().toISOString() }) + '\n', { mode: 0o600 });
      return () => {
        try {
          const owner = JSON.parse(fs.readFileSync(path.join(lock, 'owner.json'), 'utf8'));
          if (owner.pid !== process.pid || owner.nonce !== nonce) return;
        } catch { return; }
        try { fs.unlinkSync(path.join(lock, 'owner.json')); } catch { /* ignore */ }
        try { fs.rmdirSync(lock); } catch { /* ignore */ }
      };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (reclaimStaleLock(lock)) continue;
      if (Date.now() >= deadline) throw new Error('another model-routing configuration is active; retry after it completes');
      sleep(50);
    }
  }
}

function atomicWriteFile(file, data, mode = 0o600) {
  const dir = path.dirname(file);
  fs.mkdirSync(dir, { recursive: true });
  if (fs.existsSync(file)) {
    const stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) throw new Error(`transaction target is not a safe regular file: ${file}`);
  }
  const temp = path.join(dir, `.conductor-atomic.${process.pid}.${Date.now()}.${crypto.randomBytes(5).toString('hex')}.tmp`);
  let fd;
  try {
    fd = fs.openSync(temp, 'wx', mode);
    fs.writeFileSync(fd, data, 'utf8');
    fs.fsyncSync(fd);
    fs.closeSync(fd); fd = null;
    fs.renameSync(temp, file);
    try {
      const dirFd = fs.openSync(dir, 'r');
      fs.fsyncSync(dirFd);
      fs.closeSync(dirFd);
    } catch { /* directory fsync is not portable */ }
  } finally {
    if (fd !== undefined && fd !== null) try { fs.closeSync(fd); } catch { /* ignore */ }
    try { fs.unlinkSync(temp); } catch { /* ignore */ }
  }
}

function atomicWriteConfig(targetAbs, config) {
  const file = configPath(targetAbs);
  assertSafeTargetFile(file);
  atomicWriteFile(file, JSON.stringify(config, null, 2) + '\n', 0o600);
}

function digest(contents) {
  return crypto.createHash('sha256').update(contents).digest('hex');
}

function rolePath(tool, role) {
  if (tool === 'windsurf' && role === 'reflector') return '.devin/rules/reflector.md';
  const spec = ROLE_DIRS[tool];
  return `${spec[0]}/${role}${spec[1]}`;
}

function roleTier(root, source) {
  const sourceAbs = path.join(root, source);
  const contents = fs.readFileSync(sourceAbs, 'utf8');
  const match = contents.match(/^difficulty_tier:\s*([123])\s*$/m);
  if (!match) throw new Error(`role source '${source}' has no immutable difficulty_tier`);
  return Number(match[1]);
}

function replaceExactly(contents, pattern, replacement, label) {
  const matches = contents.match(new RegExp(pattern.source, pattern.flags.includes('g') ? pattern.flags : `${pattern.flags}g`)) || [];
  if (matches.length !== 1) throw new Error(`${label} expected exactly one native field, found ${matches.length}`);
  return contents.replace(pattern, replacement);
}

function compileRole(tool, contents, model, tier, rel) {
  if (tool === 'windsurf') {
    if (/^model\s*:/m.test(contents)) throw new Error(`${rel} contains a Windsurf-unsupported workflow model field`);
    if (!contents.includes('select **Adaptive**')) throw new Error(`${rel} is missing its Adaptive session preflight`);
    return contents;
  }
  if (tool === 'codex') {
    let next = replaceExactly(contents, /^model\s*=\s*"[^"]*"\s*$/m, `model = "${model}"`, `${rel} model`);
    const effort = { 1: 'high', 2: 'medium', 3: 'low' }[tier];
    next = replaceExactly(next, /^model_reasoning_effort\s*=\s*"[^"]*"\s*$/m, `model_reasoning_effort = "${effort}"`, `${rel} reasoning effort`);
    return next;
  }
  return replaceExactly(contents, /^model:\s*\S+\s*$/m, `model: ${model}`, `${rel} model`);
}

function transactionPathAllowed(rel) {
  if (rel === CONFIG_REL) return true;
  if (rel === '.devin/rules/reflector.md') return true;
  if (/^\.conductor\/manifests\/(claude|cursor|copilot|gemini|codex|windsurf)\.json$/.test(rel)) return true;
  return Object.entries(ROLE_DIRS).some(([tool, spec]) => {
    const prefix = `${spec[0]}/`;
    return rel.startsWith(prefix) && rel.endsWith(spec[1]) && /^[A-Za-z0-9-]+$/.test(rel.slice(prefix.length, -spec[1].length));
  });
}

function readTransactionJournal(targetAbs) {
  const file = path.join(targetAbs, TRANSACTION_REL);
  if (!fs.existsSync(file)) return null;
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) throw new Error(`${TRANSACTION_REL} is unsafe; manual review is required`);
  let journal;
  try { journal = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { throw new Error(`${TRANSACTION_REL} is invalid: ${error.message}`); }
  if (!journal || journal.schema_version !== 1 || !Array.isArray(journal.files)) throw new Error(`${TRANSACTION_REL} has an invalid schema`);
  for (const item of journal.files) {
    pathSafety.validateRelative(item.rel, 'transaction path');
    if (!transactionPathAllowed(item.rel) || typeof item.old_base64 !== 'string' || typeof item.existed !== 'boolean') {
      throw new Error(`${TRANSACTION_REL} contains an untrusted recovery entry`);
    }
  }
  return { file, journal };
}

function recoverTransaction(targetAbs) {
  const pending = readTransactionJournal(targetAbs);
  if (!pending) return false;
  for (const item of pending.journal.files) {
    const abs = path.join(targetAbs, item.rel);
    if (item.existed) atomicWriteFile(abs, Buffer.from(item.old_base64, 'base64').toString('utf8'), item.mode || 0o600);
    else if (fs.existsSync(abs)) {
      const stat = fs.lstatSync(abs);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) throw new Error(`cannot safely recover ${item.rel}`);
      fs.unlinkSync(abs);
    }
  }
  fs.unlinkSync(pending.file);
  return true;
}

function acquireInstallLock(targetAbs) {
  const release = acquireLock(targetAbs);
  try {
    recoverTransaction(targetAbs);
    return release;
  } catch (error) {
    release();
    throw error;
  }
}

function patchManifestSha(contents, rel, oldSha, newSha) {
  const lines = contents.split('\n');
  let found = 0;
  const updated = lines.map((line) => {
    if (!line.includes(`"path": ${JSON.stringify(rel)}`)) return line;
    if (!line.includes(`"sha256": ${JSON.stringify(oldSha)}`)) throw new Error(`manifest checksum field for '${rel}' is not canonical`);
    found++;
    return line.replace(`"sha256": ${JSON.stringify(oldSha)}`, `"sha256": ${JSON.stringify(newSha)}`);
  });
  if (found !== 1) throw new Error(`manifest ownership for '${rel}' is ambiguous (${found} entries)`);
  return updated.join('\n');
}

function prepareRoleRefresh(targetAbs, selected, next) {
  const plans = [];
  for (const tool of selected) {
    const manifestRel = `.conductor/manifests/${tool}.json`;
    const manifestAbs = path.join(targetAbs, manifestRel);
    if (!fs.existsSync(manifestAbs)) continue;
    const manifest = pathSafety.validateManifest(manifestAbs, targetAbs, tool);
    let manifestContents = fs.readFileSync(manifestAbs, 'utf8');
    let changed = false;
    for (const entry of manifest.emitted_files) {
      const sourceMatch = typeof entry.source === 'string' && entry.source.match(/^core\/roles\/([A-Za-z0-9-]+)\.md$/);
      if (!sourceMatch) continue;
      const role = sourceMatch[1];
      const expectedRel = rolePath(tool, role);
      if (entry.path !== expectedRel) throw new Error(`${tool} manifest maps role '${role}' to unexpected path '${entry.path}'`);
      const abs = path.join(targetAbs, entry.path);
      if (!fs.existsSync(abs)) throw new Error(`${tool} managed role is missing: ${entry.path}`);
      const oldContents = fs.readFileSync(abs, 'utf8');
      const oldSha = digest(oldContents);
      if (oldSha !== entry.sha256) throw new Error(`${tool} managed role was modified; refusing model reconfiguration: ${entry.path}`);
      const tier = roleTier(path.resolve(__dirname, '..'), entry.source);
      const model = next.adapters[tool].tiers[String(tier)].resolved;
      const newContents = compileRole(tool, oldContents, model, tier, entry.path);
      if (newContents === oldContents) continue;
      const newSha = digest(newContents);
      plans.push({ rel: entry.path, data: newContents, mode: fs.statSync(abs).mode & 0o777 });
      manifestContents = patchManifestSha(manifestContents, entry.path, oldSha, newSha);
      changed = true;
    }
    if (changed) plans.push({ rel: manifestRel, data: manifestContents, mode: fs.statSync(manifestAbs).mode & 0o777 });
  }
  return plans;
}

function applyConfigurationTransaction(targetAbs, rolePlans, next) {
  const configData = JSON.stringify(next, null, 2) + '\n';
  const plans = [...rolePlans, { rel: CONFIG_REL, data: configData, mode: 0o600 }];
  const journalFile = path.join(targetAbs, TRANSACTION_REL);
  const journal = {
    schema_version: 1,
    nonce: crypto.randomBytes(16).toString('hex'),
    created_at: new Date().toISOString(),
    files: plans.map((plan) => {
      const abs = path.join(targetAbs, plan.rel);
      const existed = fs.existsSync(abs);
      const old = existed ? fs.readFileSync(abs) : Buffer.alloc(0);
      return { rel: plan.rel, existed, mode: existed ? fs.statSync(abs).mode & 0o777 : plan.mode, old_base64: old.toString('base64') };
    }),
  };
  atomicWriteFile(journalFile, JSON.stringify(journal, null, 2) + '\n', 0o600);
  try {
    let writes = 0;
    for (const plan of plans) {
      atomicWriteFile(path.join(targetAbs, plan.rel), plan.data, plan.mode);
      writes++;
      if (Number(process.env.CONDUCTOR_TEST_CRASH_MODEL_TRANSACTION_AFTER) === writes) process.exit(86);
      if (Number(process.env.CONDUCTOR_TEST_FAIL_MODEL_TRANSACTION_AFTER) === writes) throw new Error('injected model-routing transaction failure');
    }
    fs.unlinkSync(journalFile);
  } catch (error) {
    try { recoverTransaction(targetAbs); }
    catch (recoveryError) { throw new Error(`${error.message}; automatic rollback also failed: ${recoveryError.message}`); }
    throw error;
  }
}

function recommendationLines(targets) {
  const display = { claude: 'Claude Code', cursor: 'Cursor', copilot: 'GitHub Copilot', gemini: 'Gemini CLI', codex: 'Codex', windsurf: 'Windsurf' };
  return targets.map((tool) => {
    const r = RECOMMENDED[tool];
    const suffix = tool === 'windsurf' ? ' (session advisory)' : '';
    return `  ${display[tool].padEnd(15)} Tier 1 ${r[1]} | Tier 2 ${r[2]} | Tier 3 ${r[3]}${suffix}`;
  });
}

async function collectChoices(targets, ask, output) {
  output.write('\nCONDUCTOR model routing — one-time project setup\n');
  output.write('Difficulty definitions are fixed; only their native model translations are configurable.\n\n');
  output.write(recommendationLines(targets).join('\n') + '\n\n');
  const whole = String(await ask('Use all recommended mappings? [Y/customize] ')).trim().toLowerCase();
  const choices = {};
  if (!whole || whole === 'y' || whole === 'yes') {
    for (const tool of targets) choices[tool] = { ...RECOMMENDED[tool] };
    return choices;
  }
  if (!['c', 'custom', 'customize', 'n', 'no'].includes(whole)) throw new Error("answer 'Y' or 'customize'");
  for (const tool of targets) {
    const rec = RECOMMENDED[tool];
    if (tool === 'windsurf') {
      output.write('Windsurf workflows cannot pin exact models; Adaptive will be stored as an advisory session requirement.\n');
      choices[tool] = { ...rec };
      continue;
    }
    const use = String(await ask(`Use recommended mapping for ${tool}? [Y/customize] `)).trim().toLowerCase();
    if (!use || use === 'y' || use === 'yes') {
      choices[tool] = { ...rec };
      continue;
    }
    if (!['c', 'custom', 'customize', 'n', 'no'].includes(use)) throw new Error("answer 'Y' or 'customize'");
    choices[tool] = {};
    for (const tier of [1, 2, 3]) {
      const answer = String(await ask(`${tool} Tier ${tier} (${TIER_LABELS[tier]}) [${rec[tier]}]: `)).trim();
      choices[tool][tier] = answer || rec[tier];
    }
  }
  return choices;
}

function defaultChoices(targets) {
  return Object.fromEntries(targets.map((tool) => [tool, { ...RECOMMENDED[tool] }]));
}

function repairableBase(prior, generatorVersion, selected) {
  const adapters = {};
  const invalidUnselected = [];
  if (prior && prior.adapters && typeof prior.adapters === 'object') {
    for (const [tool, entry] of Object.entries(prior.adapters)) {
      if (selected.includes(tool)) continue;
      if (!TOOLS.includes(tool) || validateAdapterEntry(tool, entry)) invalidUnselected.push(tool);
      else adapters[tool] = JSON.parse(JSON.stringify(entry));
    }
  }
  if (invalidUnselected.length) {
    throw new Error(`--force cannot discard invalid unselected adapter state (${invalidUnselected.join(', ')}); include every named adapter in this repair or review the file manually`);
  }
  return {
    schema_version: SCHEMA_VERSION,
    config_revision: prior && Number.isInteger(prior.config_revision) && prior.config_revision > 0 ? prior.config_revision : 0,
    generator_version: generatorVersion,
    adapters,
  };
}

async function configure({ targetAbs, targets, choices, generatorVersion, dryRun = false, force = false }) {
  const selected = [...new Set(targets)];
  if (!selected.length || selected.some((tool) => !TOOLS.includes(tool))) throw new Error('invalid or empty adapter selection');
  pathSafety.assertSafeManagedPaths(targetAbs, selected);
  if (dryRun) {
    const prior = loadConfig(targetAbs, { allowInvalid: force });
    const priorProblem = prior && validateConfig(prior);
    if (priorProblem && !force) throw new Error(`${CONFIG_REL} is invalid; rerun models configure --force after reviewing it`);
    const now = new Date().toISOString();
    const built = {};
    for (const tool of selected) built[tool] = buildAdapter(tool, choices[tool], targetAbs, now);
    const next = prior && !priorProblem ? JSON.parse(JSON.stringify(prior)) : repairableBase(prior, generatorVersion, selected);
    next.config_revision = (Number(next.config_revision) || 0) + 1;
    next.generator_version = generatorVersion;
    next.updated_at = now;
    next.adapters = { ...(next.adapters || {}), ...built };
    return next;
  }
  const release = acquireLock(targetAbs);
  try {
    recoverTransaction(targetAbs);
    const prior = loadConfig(targetAbs, { allowInvalid: force });
    const priorProblem = prior && validateConfig(prior);
    if (priorProblem && !force) throw new Error(`${CONFIG_REL} is invalid; rerun models configure --force after reviewing it`);
    if (prior && !priorProblem && !force && selected.every((tool) => {
      const entry = prior.adapters && prior.adapters[tool];
      return entry && [1, 2, 3].every((tier) => entry.tiers[String(tier)].resolved === choices[tool][tier]);
    })) return prior;

    const now = new Date().toISOString();
    const built = {};
    for (const tool of selected) built[tool] = buildAdapter(tool, choices[tool], targetAbs, now);
    const next = prior && !priorProblem ? JSON.parse(JSON.stringify(prior)) : repairableBase(prior, generatorVersion, selected);
    next.schema_version = SCHEMA_VERSION;
    next.config_revision = (Number(next.config_revision) || 0) + 1;
    next.generator_version = generatorVersion;
    next.updated_at = now;
    next.adapters = { ...(next.adapters || {}), ...built };
    const rolePlans = prepareRoleRefresh(targetAbs, selected, next);
    applyConfigurationTransaction(targetAbs, rolePlans, next);
    return next;
  } finally { release(); }
}

function missingTargets(config, targets) {
  return targets.filter((tool) => !config || !config.adapters || !config.adapters[tool] || validateAdapterEntry(tool, config.adapters[tool]));
}

function envForConfig(config, targets) {
  const env = {};
  for (const tool of targets) {
    const entry = config.adapters[tool];
    if (!entry) continue;
    const prefix = `CONDUCTOR_${tool.toUpperCase()}_MODEL_TIER_`;
    for (const tier of [1, 2, 3]) env[`${prefix}${tier}`] = entry.tiers[String(tier)].resolved;
  }
  return env;
}

function show(config, targets) {
  const lines = [];
  for (const tool of targets) {
    const entry = config && config.adapters && config.adapters[tool];
    if (!entry) { lines.push(`${tool}: UNCONFIGURED`); continue; }
    const models = [1, 2, 3].map((tier) => `Tier ${tier}=${entry.tiers[String(tier)].resolved}`).join(' | ');
    lines.push(`${tool}: ${models} | ${entry.enforcement}`);
  }
  return lines.join('\n');
}

function resolveConfigured(targetAbs, tool) {
  if (!TOOLS.includes(tool)) throw new Error(`unknown adapter '${tool}'`);
  pathSafety.assertSafeManagedPaths(targetAbs, [tool]);
  const config = loadConfig(targetAbs);
  if (!config) throw new Error(`${CONFIG_REL} is missing`);
  const problem = validateConfig(config);
  if (problem) throw new Error(`${CONFIG_REL} is invalid: ${problem}`);
  const entry = config.adapters && config.adapters[tool];
  const entryProblem = validateAdapterEntry(tool, entry);
  if (entryProblem) throw new Error(`${tool} model routing is not configured: ${entryProblem}`);
  return [1, 2, 3].map((tier) => entry.tiers[String(tier)].resolved);
}

module.exports = {
  CONFIG_REL, RECOMMENDED, SCHEMA_VERSION, TOOLS,
  acquireInstallLock, collectChoices, configure, defaultChoices, envForConfig, loadConfig,
  missingTargets, recommendationLines, resolveConfigured, show,
  validateAdapterEntry, validateConfig, validateModel,
};

if (require.main === module) {
  const [command, target, tool] = process.argv.slice(2);
  if (command !== 'resolve' || !target || !tool) {
    process.stderr.write('Usage: node bin/model-routing.js resolve <target-project> <adapter>\n');
    process.exit(2);
  }
  try {
    const targetAbs = path.resolve(process.cwd(), target);
    for (const model of resolveConfigured(targetAbs, tool)) process.stdout.write(`${model}\n`);
  } catch (error) {
    process.stderr.write(`CONDUCTOR model routing check failed: ${error.message}\n`);
    process.exit(2);
  }
}
