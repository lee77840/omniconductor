#!/usr/bin/env node
'use strict';

/*
 * omniconductor — thin dispatcher to the per-tool adapter transform scripts.
 *
 * Usage:
 *   omniconductor init --target=<tool> [target-dir] [--recipes=a,b] [--dry-run] [--no-prompt]
 *   omniconductor init --target=<tool> [target-dir] --uninstall [--force]
 *   omniconductor models configure --target=<tool|all> [target-dir]
 *   omniconductor models show [target-dir]
 *   omniconductor doctor [target-dir] [--json]
 *   omniconductor audit extensions [target-dir] [--target=<tool|all>] [--json]
 *   omniconductor eval coverage [--json] [--compare=<report.json>]
 *   omniconductor work claim|status|handoff|release ...
 *   omniconductor workspace doctor [workspace-dir] [--json]
 *   omniconductor skills propose|list|review ...
 *   omniconductor package --target=<tool|all> <output-dir> [--force] [--strict-native]
 *   omniconductor list
 *   omniconductor --help | --version
 *
 * It does NOT reimplement any install logic. It locates this repo's
 * adapters/<tool>/transform.sh and runs it with `bash`, forwarding all flags
 * and inheriting stdio. The shell adapters remain the single source of truth
 * (ADR-002/023/025 — the bash adapters are the validated implementation).
 * `doctor` (ADR-041) is read-only: it inspects an install, never changes it.
 */

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');
const readline = require('readline/promises');
const modelRouting = require('./model-routing.js');
const pathSafety = require('./path-safety.js');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];

function readVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')).version || 'unknown';
  } catch {
    return 'unknown';
  }
}

function usage() {
  return `omniconductor ${readVersion()} — install CONDUCTOR's workflow into an AI coding tool

Usage:
  omniconductor init --target=<tool> [target-dir] [options]   Install into target-dir (default: .)
  omniconductor models configure --target=<tool|all> [dir]   Set Tier 1/2/3 models once
  omniconductor models show [target-dir]                     Show saved model routing
  omniconductor doctor [target-dir] [--json]                  Health-check an existing install (read-only)
  omniconductor audit extensions [target-dir] [options]       Audit extension/MCP trust (read-only)
  omniconductor eval coverage [--json] [--compare=<file>]     Report evidence-backed policy coverage
  omniconductor work claim <task> [dir] --tool=<t> --session=<id> [--scope=<path>]
  omniconductor work status [dir] [--json]                    Inspect local clone/worktree claims
  omniconductor work handoff <task> [dir] --tool=<t> --session=<id> --to-tool=<t> --to-session=<id>
  omniconductor work release <task> [dir] --tool=<t> --session=<id>
  omniconductor workspace doctor [dir] [--json]               Validate a multi-repo workspace (read-only)
  omniconductor skills propose [dir] --from=<file>             Add a pending, propose-only skill item
  omniconductor skills list [dir] [--json]                     List skill proposal inbox items
  omniconductor skills review <id> [dir] --decision=<d>        Record accept|reject; never auto-apply
  omniconductor package --target=<tool|all> <output-dir>        Build optional provider packages
  omniconductor list                                          List available tool adapters
  omniconductor --help | --version

Tools: ${TOOLS.join(', ')}, all

Common options (forwarded to the adapter):
  --recipes=a,b,c     Opt-in recipes to install
  --mode=<m>          Install preset: full (default) | minimal | strict |
                      recipes-only | reflector-only (ADR-044)
  --dry-run           Preview only — write nothing
  --no-prompt         Skip interactive prompts (CI-safe)
  --accept-model-defaults
                      Accept documented model recommendations without prompting
  --uninstall         Revert a previous install (manifest-based)
  --force             Bypass uninstall safety checks

Examples:
  omniconductor init --target=claude ./my-app --recipes=tdd,debugging
  omniconductor init --target=cursor ./my-app --dry-run
  omniconductor init --target=all ./my-app --no-prompt
  omniconductor init --target=all ./my-app --no-prompt --accept-model-defaults
  omniconductor models configure --target=codex ./my-app
  omniconductor models show ./my-app
  omniconductor init --target=codex . --uninstall
  omniconductor doctor ./my-app --json
  omniconductor audit extensions ./my-app --target=all --json
  omniconductor eval coverage --json

Run:  npx omniconductor init --target=<tool> <dir>`;
}

function fail(msg) {
  process.stderr.write(`omniconductor: ${msg}\n\n`);
  process.stderr.write(usage() + '\n');
  process.exit(2);
}

function parseTargetAndDir(args, { defaultTarget = null } = {}) {
  let target = defaultTarget;
  let targetDir = null;
  const passthrough = [];
  for (const a of args) {
    if (a.startsWith('--target=')) {
      target = a.slice('--target='.length);
    } else if (a === '--target') {
      fail('use --target=<tool> (with =), e.g. --target=claude');
    } else if (a.startsWith('-')) {
      passthrough.push(a);
    } else if (targetDir === null) {
      targetDir = a;
    } else {
      passthrough.push(a);
    }
  }
  return { target, targetDir: targetDir || '.', passthrough };
}

function selectedTools(target) {
  if (!target) fail('missing --target=<tool>');
  if (!TOOLS.includes(target) && target !== 'all') {
    fail(`unknown target '${target}'. One of: ${TOOLS.join(', ')}, all`);
  }
  return target === 'all' ? [...TOOLS] : [target];
}

function runAdapterTransform(transform, args, env) {
  let proofFd;
  try {
    proofFd = fs.openSync(__filename, 'r');
    return spawnSync('bash', [transform, ...args], {
      stdio: ['inherit', 'inherit', 'inherit', proofFd],
      env: { ...env, CONDUCTOR_CLI_DISPATCH: '1' },
    });
  } finally {
    if (proofFd !== undefined) try { fs.closeSync(proofFd); } catch { /* ignore */ }
  }
}

function preserveLegacyManifestBeforeAllInstall(targetAbs) {
  const legacy = path.join(targetAbs, '.conductor-manifest.json');
  if (!fs.existsSync(legacy)) return;
  let parsed;
  try { parsed = JSON.parse(fs.readFileSync(legacy, 'utf8')); }
  catch (error) { throw new Error(`legacy root manifest is invalid JSON: ${error.message}`); }
  const adapter = parsed && parsed.adapter;
  if (!TOOLS.includes(adapter) || parsed.manifest_scope === 'aggregate') return;
  const destination = path.join(targetAbs, '.conductor', 'manifests', `${adapter}.json`);
  if (fs.existsSync(destination)) return;
  pathSafety.validateManifest(legacy, targetAbs, adapter, { allowLegacy: true });
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const scoped = { ...parsed, schema_version: 2, manifest_scope: 'adapter', adapter };
  const entries = scoped.emitted_files;
  delete scoped.emitted_files;
  const header = JSON.stringify(scoped, null, 2).replace(/\n}$/, '');
  const entryLines = entries.map((entry) => `    ${JSON.stringify(entry)}`).join(',\n');
  fs.writeFileSync(destination, `${header},\n  "emitted_files": [\n${entryLines}\n  ]\n}\n`, { flag: 'wx', mode: 0o600 });
  pathSafety.validateManifest(destination, targetAbs, adapter);
  process.stderr.write(`omniconductor: preserved legacy ${adapter} ownership before six-tool migration\n`);
}

async function askForChoices(targets) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error('model setup needs an interactive terminal; rerun with --accept-model-defaults or run `omniconductor models configure` in a terminal');
  }
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    return await modelRouting.collectChoices(targets, (question) => rl.question(question), process.stdout);
  } finally { rl.close(); }
}

async function configureMissingModels({ targetAbs, targets, noPrompt, acceptDefaults, dryRun, force = false, reconfigure = false }) {
  let config = modelRouting.loadConfig(targetAbs, { allowInvalid: force });
  const missing = reconfigure ? targets : modelRouting.missingTargets(config, targets);
  if (!missing.length) return config;
  let choices;
  if (acceptDefaults || dryRun) {
    choices = modelRouting.defaultChoices(missing);
  } else if (noPrompt) {
    throw new Error(`model routing is not configured for: ${missing.join(', ')}. Run \`omniconductor models configure --target=${missing.length === TOOLS.length ? 'all' : missing[0]} ${targetAbs}\` or add --accept-model-defaults`);
  } else {
    choices = await askForChoices(missing);
  }
  config = await modelRouting.configure({
    targetAbs, targets: missing, choices, generatorVersion: readVersion(), dryRun, force,
  });
  if (!dryRun) process.stderr.write(`omniconductor: saved model routing in ${path.join(targetAbs, modelRouting.CONFIG_REL)}\n`);
  else process.stderr.write(`omniconductor: dry-run would configure model routing for ${missing.join(', ')}\n`);
  return config;
}

async function main(argv) {
  const args = argv.slice(2);

  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    process.stdout.write(usage() + '\n');
    return 0;
  }
  if (args.includes('--version') || args.includes('-v')) {
    process.stdout.write(readVersion() + '\n');
    return 0;
  }

  const cmd = args[0];

  if (cmd === 'list') {
    process.stdout.write('Available adapters:\n');
    for (const t of TOOLS) {
      const present = fs.existsSync(path.join(ROOT, 'adapters', t, 'transform.sh'));
      process.stdout.write(`  ${t.padEnd(9)} ${present ? '✅ transform.sh' : '⏳ not implemented'}\n`);
    }
    return 0;
  }

  if (cmd === 'doctor') {
    const rest = args.slice(1);
    const jsonOut = rest.includes('--json');
    const dir = rest.find((a) => !a.startsWith('-')) || '.';
    return require('./doctor.js').run(dir, { json: jsonOut });
  }

  if (cmd === 'audit') {
    const action = args[1];
    if (action !== 'extensions') fail("audit expects 'extensions'");
    const parsed = parseTargetAndDir(args.slice(2), { defaultTarget: 'all' });
    const targets = selectedTools(parsed.target);
    const known = new Set(['--json']);
    const unknown = parsed.passthrough.filter((a) => !known.has(a));
    if (unknown.length) fail(`unknown audit option(s): ${unknown.join(', ')}`);
    try {
      const extensionTrust = require('./extension-trust.js');
      const report = extensionTrust.audit(parsed.targetDir, targets);
      process.stdout.write(parsed.passthrough.includes('--json')
        ? `${JSON.stringify(report, null, 2)}\n`
        : `${extensionTrust.render(report)}\n`);
      return report.summary.high ? 1 : 0;
    } catch (error) {
      process.stderr.write(`omniconductor: extension audit failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd === 'eval') {
    if (args[1] !== 'coverage') fail("eval expects 'coverage'");
    const rest = args.slice(2);
    const known = rest.every((arg) => arg === '--json' || arg === '--format=json' || arg.startsWith('--compare='));
    if (!known) fail(`unknown eval coverage option(s): ${rest.filter((arg) => arg !== '--json' && arg !== '--format=json' && !arg.startsWith('--compare=')).join(', ')}`);
    const compareArg = rest.find((arg) => arg.startsWith('--compare='));
    if (rest.filter((arg) => arg.startsWith('--compare=')).length > 1) fail('eval coverage accepts one --compare=<report.json>');
    try {
      const assurance = require('./assurance-coverage.js');
      const report = assurance.buildReport();
      let regressions = [];
      if (compareArg) {
        const comparisonPath = path.resolve(compareArg.slice('--compare='.length));
        const stat = fs.lstatSync(comparisonPath);
        if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 8 * 1024 * 1024) {
          throw new Error('comparison report must be a safe regular JSON file no larger than 8 MiB');
        }
        regressions = assurance.compare(report, JSON.parse(fs.readFileSync(comparisonPath, 'utf8')));
      }
      process.stdout.write(rest.includes('--json') || rest.includes('--format=json')
        ? `${JSON.stringify(report, null, 2)}\n`
        : `${assurance.render(report)}\n`);
      if (regressions.length) {
        for (const regression of regressions) process.stderr.write(`omniconductor: coverage regression: ${regression}\n`);
        return 1;
      }
      return 0;
    } catch (error) {
      process.stderr.write(`omniconductor: assurance coverage failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd === 'work') {
    const workContract = require('./work-contract.js');
    const action = args[1];
    if (!['claim', 'status', 'handoff', 'release'].includes(action)) {
      fail("work expects 'claim', 'status', 'handoff', or 'release'");
    }
    const rest = args.slice(2);
    const value = (name) => {
      const prefix = `--${name}=`;
      const match = rest.find((arg) => arg.startsWith(prefix));
      return match ? match.slice(prefix.length) : null;
    };
    const values = (name) => {
      const prefix = `--${name}=`;
      return rest.filter((arg) => arg.startsWith(prefix)).map((arg) => arg.slice(prefix.length));
    };
    const allowed = {
      claim: new Set(['tool', 'session', 'scope', 'json']),
      status: new Set(['json']),
      handoff: new Set(['tool', 'session', 'to-tool', 'to-session', 'note', 'json']),
      release: new Set(['tool', 'session', 'note', 'json']),
    }[action];
    const unknown = rest.filter((arg) => arg.startsWith('--')).filter((arg) => !allowed.has(arg.slice(2).split('=')[0]));
    if (unknown.length) fail(`unknown work option(s): ${unknown.join(', ')}`);
    for (const name of allowed) {
      if (name === 'scope') continue;
      if (values(name).length > 1) fail(`work ${action} accepts one --${name}= value`);
    }
    const positionals = rest.filter((arg) => !arg.startsWith('-'));
    try {
      let result;
      if (action === 'status') {
        if (positionals.length > 1) fail('work status accepts at most one directory');
        result = workContract.inspect(positionals[0] || '.');
        process.stdout.write(rest.includes('--json') ? `${JSON.stringify(result, null, 2)}\n` : `${workContract.render(result)}\n`);
        return result.summary.failures ? 1 : 0;
      }
      const task = positionals[0];
      if (!task) fail(`work ${action} requires a task id`);
      if (positionals.length > 2) fail(`work ${action} accepts one optional directory`);
      const dir = positionals[1] || '.';
      const owner = { tool: value('tool'), session: value('session') };
      if (!owner.tool || !owner.session) fail(`work ${action} requires --tool=<tool> and --session=<id>`);
      if (action === 'claim') {
        result = workContract.claim(dir, task, { ...owner, scopes: values('scope') });
      } else if (action === 'handoff') {
        const toTool = value('to-tool');
        const toSession = value('to-session');
        if (!toTool || !toSession) fail('work handoff requires --to-tool=<tool> and --to-session=<id>');
        result = workContract.handoff(dir, task, { ...owner, toTool, toSession, note: value('note') || '' });
      } else {
        result = workContract.releaseClaim(dir, task, { ...owner, note: value('note') || '' });
      }
      process.stdout.write(rest.includes('--json')
        ? `${JSON.stringify(result, null, 2)}\n`
        : `${action === 'claim' ? (result.resumed ? 'Resumed' : result.created ? 'Claimed' : 'Already claimed') : action === 'handoff' ? 'Handed off' : 'Released'} ${task}: ${result.record.status} · ${result.record.owner.tool}/${result.record.owner.session}\n`);
      return 0;
    } catch (error) {
      process.stderr.write(`omniconductor: work ${action} failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd === 'workspace') {
    if (args[1] !== 'doctor') fail("workspace expects 'doctor'");
    const rest = args.slice(2);
    const unknown = rest.filter((arg) => arg.startsWith('-') && arg !== '--json');
    if (unknown.length) fail(`unknown workspace doctor option(s): ${unknown.join(', ')}`);
    const positionals = rest.filter((arg) => !arg.startsWith('-'));
    if (positionals.length > 1) fail('workspace doctor accepts at most one directory');
    try {
      const workspace = require('./workspace-contract.js');
      const report = workspace.inspect(positionals[0] || '.');
      process.stdout.write(rest.includes('--json') ? `${JSON.stringify(report, null, 2)}\n` : `${workspace.render(report)}\n`);
      return report.summary.FAIL ? 2 : report.summary.WARN ? 1 : 0;
    } catch (error) {
      process.stderr.write(`omniconductor: workspace doctor failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd === 'skills') {
    const skillProposals = require('./skill-proposals.js');
    const action = args[1];
    const rest = args.slice(2);
    const option = (name) => {
      const prefix = `--${name}=`;
      const value = rest.find((arg) => arg.startsWith(prefix));
      return value ? value.slice(prefix.length) : null;
    };
    const allowedFor = {
      propose: new Set(['from', 'dry-run', 'json']),
      list: new Set(['json']),
      review: new Set(['decision', 'note', 'json']),
    };
    if (!allowedFor[action]) fail("skills expects 'propose', 'list', or 'review'");
    const unknown = rest.filter((arg) => arg.startsWith('--')).filter((arg) => {
      const name = arg.slice(2).split('=')[0];
      return !allowedFor[action].has(name);
    });
    if (unknown.length) fail(`unknown skills option(s): ${unknown.join(', ')}`);
    try {
      if (action === 'propose') {
        const positionals = rest.filter((arg) => !arg.startsWith('-'));
        if (positionals.length > 1) fail('skills propose accepts at most one directory');
        const dir = positionals[0] || '.';
        const inputFile = option('from');
        if (!inputFile) fail('skills propose requires --from=<proposal.json>');
        const stat = fs.lstatSync(path.resolve(inputFile));
        if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 256 * 1024) {
          throw new Error('proposal input must be a regular JSON file no larger than 256 KiB');
        }
        const input = JSON.parse(fs.readFileSync(path.resolve(inputFile), 'utf8'));
        const result = skillProposals.create(dir, input, { dryRun: rest.includes('--dry-run') });
        process.stdout.write(rest.includes('--json')
          ? `${JSON.stringify(result, null, 2)}\n`
          : `${result.created ? 'Created' : result.dry_run ? 'Would create' : 'Already exists'} skill proposal ${result.proposal.id}: ${result.file}\n`);
        return 0;
      }
      if (action === 'list') {
        const positionals = rest.filter((arg) => !arg.startsWith('-'));
        if (positionals.length > 1) fail('skills list accepts at most one directory');
        const dir = positionals[0] || '.';
        const proposals = skillProposals.list(dir);
        process.stdout.write(rest.includes('--json')
          ? `${JSON.stringify(proposals, null, 2)}\n`
          : `${skillProposals.render(proposals)}\n`);
        return 0;
      }
      const id = rest[0];
      if (!id || id.startsWith('-')) fail('skills review requires a proposal id');
      const positionals = rest.slice(1).filter((arg) => !arg.startsWith('-'));
      if (positionals.length > 1) fail('skills review accepts at most one directory');
      const dir = positionals[0] || '.';
      const decision = option('decision');
      if (!decision) fail('skills review requires --decision=accept|reject');
      const proposal = skillProposals.review(dir, id, decision, option('note') || undefined);
      process.stdout.write(rest.includes('--json')
        ? `${JSON.stringify(proposal, null, 2)}\n`
        : `Recorded ${proposal.status} for ${proposal.id}; applied=false\n`);
      return 0;
    } catch (error) {
      process.stderr.write(`omniconductor: skill proposal command failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd === 'package') {
    const parsed = parseTargetAndDir(args.slice(1));
    const targets = selectedTools(parsed.target);
    const known = new Set(['--force', '--strict-native', '--dry-run', '--json']);
    const unknown = parsed.passthrough.filter((arg) => !known.has(arg));
    if (unknown.length) fail(`unknown package option(s): ${unknown.join(', ')}`);
    if (parsed.targetDir === '.') fail('package requires an explicit output directory');
    try {
      const packager = require('./plugin-packager.js');
      const result = packager.build(parsed.targetDir, targets, {
        force: parsed.passthrough.includes('--force'),
        strictNative: parsed.passthrough.includes('--strict-native'),
        dryRun: parsed.passthrough.includes('--dry-run'),
      });
      process.stdout.write(parsed.passthrough.includes('--json')
        ? `${JSON.stringify(result, null, 2)}\n`
        : `${result.dry_run ? 'Would build' : 'Built'} ${result.packages.length} package(s) in ${result.output}\n${result.packages.map((item) => `  ${item.tool}: ${item.mode} → ${item.directory}`).join('\n')}\n`);
      return 0;
    } catch (error) {
      process.stderr.write(`omniconductor: package build failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd === 'models') {
    const action = args[1];
    if (action === 'show') {
      const rest = args.slice(2);
      const dir = rest.find((a) => !a.startsWith('-')) || '.';
      const targetAbs = path.resolve(process.cwd(), dir);
      let config;
      try { config = modelRouting.loadConfig(targetAbs); }
      catch (error) { process.stderr.write(`omniconductor: ${error.message}\n`); return 2; }
      process.stdout.write(modelRouting.show(config, TOOLS) + '\n');
      return config ? 0 : 1;
    }
    if (action !== 'configure') fail("models expects 'configure' or 'show'");
    const parsed = parseTargetAndDir(args.slice(2), { defaultTarget: 'all' });
    const targets = selectedTools(parsed.target);
    const known = new Set(['--no-prompt', '--accept-model-defaults', '--force', '--dry-run']);
    const unknown = parsed.passthrough.filter((a) => !known.has(a));
    if (unknown.length) fail(`unknown models option(s): ${unknown.join(', ')}`);
    const targetAbs = path.resolve(process.cwd(), parsed.targetDir);
    if (!fs.existsSync(targetAbs) || !fs.statSync(targetAbs).isDirectory()) {
      process.stderr.write(`omniconductor: target directory does not exist: ${targetAbs}\n`);
      return 2;
    }
    try {
      pathSafety.assertSafeManagedPaths(targetAbs, targets);
      const config = await configureMissingModels({
        targetAbs,
        targets,
        noPrompt: parsed.passthrough.includes('--no-prompt'),
        acceptDefaults: parsed.passthrough.includes('--accept-model-defaults'),
        dryRun: parsed.passthrough.includes('--dry-run'),
        force: parsed.passthrough.includes('--force'),
        reconfigure: true,
      });
      process.stdout.write(modelRouting.show(config, targets) + '\n');
      return 0;
    } catch (error) {
      process.stderr.write(`omniconductor: model configuration failed: ${error.message}\n`);
      return 2;
    }
  }

  if (cmd !== 'init') {
    fail(`unknown command '${cmd}'. Expected 'init', 'models', 'doctor', 'audit', 'eval', 'work', 'workspace', 'skills', 'package', or 'list'.`);
  }

  // Parse `init` args: extract --target, the positional target-dir, forward the rest.
  const parsed = parseTargetAndDir(args.slice(1));
  const target = parsed.target;
  const dir = parsed.targetDir;
  const acceptDefaults = parsed.passthrough.includes('--accept-model-defaults');
  const passthrough = parsed.passthrough.filter((a) => a !== '--accept-model-defaults');
  const targets = selectedTools(target);
  const targetAbs = path.resolve(process.cwd(), dir);
  const uninstall = passthrough.includes('--uninstall') || passthrough.includes('--rollback');
  const dryRun = passthrough.includes('--dry-run');
  const noPrompt = passthrough.includes('--no-prompt');
  const modeArg = passthrough.find((a) => a.startsWith('--mode='));
  const mode = modeArg ? modeArg.slice('--mode='.length) : 'full';
  if (!fs.existsSync(targetAbs) || !fs.statSync(targetAbs).isDirectory()) {
    process.stderr.write(`omniconductor: target directory does not exist: ${targetAbs}\n`);
    return 2;
  }
  try {
    pathSafety.assertSafeManagedPaths(targetAbs, targets);
  } catch (error) {
    process.stderr.write(`omniconductor: unsafe target refused before any write: ${error.message}\n`);
    return 2;
  }
  let routingEnv = {};
  if (!uninstall && mode !== 'recipes-only') {
    try {
      const config = await configureMissingModels({ targetAbs, targets, noPrompt, acceptDefaults, dryRun });
      routingEnv = modelRouting.envForConfig(config, targets);
    } catch (error) {
      process.stderr.write(`omniconductor: model setup required before installation: ${error.message}\n`);
      return 2;
    }
  }
  let releaseInstallLock = null;
  if (!dryRun) {
    try { releaseInstallLock = modelRouting.acquireInstallLock(targetAbs); }
    catch (error) {
      process.stderr.write(`omniconductor: could not lock the project for installation: ${error.message}\n`);
      return 2;
    }
  }
  try {
    if (target === 'all') {
      if (!uninstall && !dryRun) {
        try { preserveLegacyManifestBeforeAllInstall(targetAbs); }
        catch (error) {
          process.stderr.write(`omniconductor: legacy manifest migration failed before installation: ${error.message}\n`);
          return 2;
        }
      }
      const ordered = uninstall ? [...TOOLS].reverse() : TOOLS;
      for (const tool of ordered) {
        const transform = path.join(ROOT, 'adapters', tool, 'transform.sh');
        if (!fs.existsSync(transform)) {
          process.stderr.write(`omniconductor: the '${tool}' adapter has no transform.sh\n`);
          return 1;
        }
        const cmdline = ['bash', transform, dir, ...passthrough];
        process.stderr.write(`omniconductor [${tool}] → ${cmdline.slice(1).join(' ')}\n`);
        const res = runAdapterTransform(transform, [dir, ...passthrough], { ...process.env, ...routingEnv });
        if (res.error || res.status !== 0) {
          const detail = res.error ? res.error.message : `exit ${res.status}`;
          process.stderr.write(`omniconductor: '${tool}' adapter failed (${detail}); prior adapter manifests remain intact for diagnosis/retry.\n`);
          return res.status === null || res.status === 0 ? 1 : res.status;
        }
      }
      return 0;
    }

    const transform = path.join(ROOT, 'adapters', target, 'transform.sh');
    if (!fs.existsSync(transform)) {
      fail(`the '${target}' adapter has no transform.sh yet (manual install — see docs/MANUAL-INSTALL.md).`);
    }

    const cmdline = ['bash', transform, dir, ...passthrough];
    process.stderr.write(`omniconductor → ${cmdline.slice(1).join(' ')}\n`);

    const res = runAdapterTransform(transform, [dir, ...passthrough], { ...process.env, ...routingEnv });
    if (res.error) {
      process.stderr.write(`omniconductor: failed to run adapter: ${res.error.message}\n`);
      return 1;
    }
    return res.status === null ? 1 : res.status;
  } finally {
    if (releaseInstallLock) releaseInstallLock();
  }
}

main(process.argv).then((code) => { process.exitCode = code; }).catch((error) => {
  process.stderr.write(`omniconductor: unexpected failure: ${error.stack || error.message}\n`);
  process.exitCode = 1;
});
