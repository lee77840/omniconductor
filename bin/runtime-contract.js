'use strict';

/*
 * Adapter runtime compatibility contracts.
 *
 * metadata.json describes static provider/runtime facts. This module validates
 * that contract and performs bounded, local-only inspection (`<cli> --version`).
 * It never authenticates, sends a prompt, reads credentials, or writes files.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
const LIFECYCLES = new Set(['active', 'renamed', 'source-conflict']);
const AUTH_STATUSES = new Set(['documented', 'policy-controlled', 'source-conflict', 'verification-required']);
const PROBE_KINDS = new Set(['local-renderer', 'headless-model', 'manual-ide']);
const FLOOR_BASES = new Set(['documented', 'live-verified']);
const VERSION_ENV_ALLOWLIST = new Set(['PATH', 'PATHEXT', 'SYSTEMROOT', 'WINDIR', 'COMSPEC']);

function loadMetadata(tool) {
  if (!TOOLS.includes(tool)) throw new Error(`unknown adapter '${tool}'`);
  return JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', tool, 'metadata.json'), 'utf8'));
}

function nonEmpty(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function validateRuntimeContract(meta) {
  const problems = [];
  const at = (condition, message) => { if (!condition) problems.push(message); };
  const contract = meta && meta.runtime_contract;

  at(meta && nonEmpty(meta.tool) && TOOLS.includes(meta.tool), `tool must be one of: ${TOOLS.join(', ')}`);
  at(meta && meta.headless_cli && nonEmpty(meta.headless_cli.command),
    'headless_cli.command must be available to the runtime contract');
  at(meta && meta.live_verification && nonEmpty(meta.live_verification.status),
    'live_verification.status must be available to the runtime contract');
  at(contract && typeof contract === 'object' && !Array.isArray(contract), 'runtime_contract must be an object');
  if (!contract || typeof contract !== 'object' || Array.isArray(contract)) return problems;

  at(contract.schema_version === 1, 'runtime_contract.schema_version must be 1');

  const product = contract.product;
  at(product && typeof product === 'object' && !Array.isArray(product), 'runtime_contract.product must be an object');
  if (product && typeof product === 'object' && !Array.isArray(product)) {
    at(nonEmpty(product.canonical_name), 'runtime_contract.product.canonical_name must be non-empty');
    at(Array.isArray(product.aliases) && product.aliases.every(nonEmpty), 'runtime_contract.product.aliases must be an array of non-empty strings');
    at(LIFECYCLES.has(product.lifecycle), `runtime_contract.product.lifecycle must be one of: ${[...LIFECYCLES].join(', ')}`);
    at(nonEmpty(product.note), 'runtime_contract.product.note must be non-empty');
  }

  const version = contract.version;
  at(version && typeof version === 'object' && !Array.isArray(version), 'runtime_contract.version must be an object');
  if (version && typeof version === 'object' && !Array.isArray(version)) {
    at(Array.isArray(version.args) && version.args.length > 0 && version.args.every(nonEmpty),
      'runtime_contract.version.args must be a non-empty string array');
    at(Array.isArray(version.capability_floors), 'runtime_contract.version.capability_floors must be an array');
    const seenCapabilities = new Set();
    for (const [index, floor] of (Array.isArray(version.capability_floors) ? version.capability_floors : []).entries()) {
      const prefix = `runtime_contract.version.capability_floors[${index}]`;
      at(floor && typeof floor === 'object' && !Array.isArray(floor), `${prefix} must be an object`);
      if (!floor || typeof floor !== 'object' || Array.isArray(floor)) continue;
      at(nonEmpty(floor.capability), `${prefix}.capability must be non-empty`);
      if (nonEmpty(floor.capability)) {
        at(!seenCapabilities.has(floor.capability), `${prefix}.capability duplicates '${floor.capability}'`);
        seenCapabilities.add(floor.capability);
      }
      at(/^\d+\.\d+\.\d+$/.test(String(floor.minimum || '')), `${prefix}.minimum must be x.y.z`);
      at(floor.when_emitted === null || nonEmpty(floor.when_emitted), `${prefix}.when_emitted must be null or a non-empty path`);
      at(FLOOR_BASES.has(floor.basis), `${prefix}.basis must be one of: ${[...FLOOR_BASES].join(', ')}`);
      at(nonEmpty(floor.source) && /^https:\/\//.test(floor.source), `${prefix}.source must be an https URL`);
    }
  }

  const auth = contract.auth;
  at(auth && typeof auth === 'object' && !Array.isArray(auth), 'runtime_contract.auth must be an object');
  if (auth && typeof auth === 'object' && !Array.isArray(auth)) {
    at(AUTH_STATUSES.has(auth.status), `runtime_contract.auth.status must be one of: ${[...AUTH_STATUSES].join(', ')}`);
    at(Array.isArray(auth.modes) && auth.modes.length > 0 && auth.modes.every(nonEmpty),
      'runtime_contract.auth.modes must be a non-empty string array');
    at(nonEmpty(auth.note), 'runtime_contract.auth.note must be non-empty');
  }

  at(Array.isArray(contract.policy_gates) && contract.policy_gates.every(nonEmpty),
    'runtime_contract.policy_gates must be an array of non-empty strings');

  const probe = contract.probe;
  at(probe && typeof probe === 'object' && !Array.isArray(probe), 'runtime_contract.probe must be an object');
  if (probe && typeof probe === 'object' && !Array.isArray(probe)) {
    at(PROBE_KINDS.has(probe.kind), `runtime_contract.probe.kind must be one of: ${[...PROBE_KINDS].join(', ')}`);
    at(typeof probe.requires_auth === 'boolean', 'runtime_contract.probe.requires_auth must be boolean');
    at(typeof probe.requires_network === 'boolean', 'runtime_contract.probe.requires_network must be boolean');
    at(nonEmpty(probe.note), 'runtime_contract.probe.note must be non-empty');
  }

  at(Array.isArray(contract.sources) && contract.sources.length > 0, 'runtime_contract.sources must be a non-empty array');
  for (const [index, source] of (Array.isArray(contract.sources) ? contract.sources : []).entries()) {
    const prefix = `runtime_contract.sources[${index}]`;
    at(source && typeof source === 'object' && !Array.isArray(source), `${prefix} must be an object`);
    if (!source || typeof source !== 'object' || Array.isArray(source)) continue;
    at(nonEmpty(source.label), `${prefix}.label must be non-empty`);
    at(nonEmpty(source.url) && /^https:\/\//.test(source.url), `${prefix}.url must be an https URL`);
    at(/^\d{4}-\d{2}-\d{2}$/.test(String(source.checked || '')), `${prefix}.checked must be YYYY-MM-DD`);
  }

  return problems;
}

function parseVersion(value) {
  const match = String(value || '').match(/(?:^|[^\d])(\d+)\.(\d+)\.(\d+)(?:[^\d]|$)/);
  if (!match) return null;
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    label: `${match[1]}.${match[2]}.${match[3]}`,
  };
}

function versionAtLeast(actual, minimum) {
  const left = typeof actual === 'string' ? parseVersion(actual) : actual;
  const right = typeof minimum === 'string' ? parseVersion(minimum) : minimum;
  if (!left || !right) return false;
  if (left.major !== right.major) return left.major > right.major;
  if (left.minor !== right.minor) return left.minor > right.minor;
  return left.patch >= right.patch;
}

function versionProbeEnv(source) {
  return Object.fromEntries(Object.entries(source || process.env)
    .filter(([name]) => VERSION_ENV_ALLOWLIST.has(name.toUpperCase())));
}

function inspectRuntime(tool, options = {}) {
  const meta = options.meta || loadMetadata(tool);
  const problems = validateRuntimeContract(meta);
  if (problems.length) {
    return {
      tool,
      status: 'invalid-contract',
      severity: 'FAIL',
      detail: problems.join('; '),
      installed: false,
      version: null,
    };
  }

  const contract = meta.runtime_contract;
  const emitted = new Set(options.emittedPaths || []);
  const runner = options.spawnSync || spawnSync;
  const command = meta.headless_cli.command;
  const result = runner(command, contract.version.args, {
    encoding: 'utf8',
    timeout: options.timeout || 5000,
    env: versionProbeEnv(options.env || process.env),
  });

  if (result.error && result.error.code === 'ENOENT') {
    return {
      tool,
      status: 'not-installed',
      severity: 'OK',
      detail: `${command} is not on PATH; emitted files remain portable but runtime activation is not locally observable`,
      installed: false,
      version: null,
    };
  }
  if (result.error || result.status !== 0) {
    return {
      tool,
      status: 'installed-unverified',
      severity: 'WARN',
      detail: `${command} is present but its local version probe did not complete successfully`,
      installed: true,
      version: null,
    };
  }

  const rawVersion = String(result.stdout || result.stderr || '').trim().slice(0, 160);
  const parsed = parseVersion(rawVersion);
  const applicableFloors = contract.version.capability_floors.filter((floor) =>
    floor.when_emitted === null || emitted.has(floor.when_emitted));
  if (applicableFloors.length && !parsed) {
    return {
      tool,
      status: 'installed-unverified',
      severity: 'WARN',
      detail: `${command} version output did not contain a parseable x.y.z version; raw output omitted`,
      installed: true,
      version: null,
    };
  }

  const unsupported = applicableFloors.filter((floor) => !versionAtLeast(parsed, floor.minimum));
  if (unsupported.length) {
    return {
      tool,
      status: 'unsupported-version',
      severity: 'WARN',
      detail: `${command} ${parsed.label} is below ${unsupported.map((floor) => `${floor.capability}>=${floor.minimum}`).join(', ')}`,
      installed: true,
      version: parsed.label,
    };
  }

  if (contract.product.lifecycle === 'source-conflict' || contract.auth.status === 'source-conflict') {
    return {
      tool,
      status: 'verification-required',
      severity: 'WARN',
      detail: `${command} ${parsed ? parsed.label : '(detected)'} is installed, but current first-party lifecycle/auth sources conflict; use the opt-in live probe`,
      installed: true,
      version: parsed ? parsed.label : null,
    };
  }

  if (meta.live_verification.status !== 'verified') {
    return {
      tool,
      status: 'installed-unverified',
      severity: 'WARN',
      detail: `${command} ${parsed ? parsed.label : '(detected)'} is installed; rule loading remains live-pending`,
      installed: true,
      version: parsed ? parsed.label : null,
    };
  }

  if (contract.product.lifecycle === 'renamed') {
    return {
      tool,
      status: 'product-migrated',
      severity: 'OK',
      detail: `${command} ${parsed ? parsed.label : '(detected)'} matches the ${contract.product.canonical_name} product line (${contract.product.aliases.join(', ')} compatibility retained)`,
      installed: true,
      version: parsed ? parsed.label : null,
    };
  }

  return {
    tool,
    status: 'active',
    severity: 'OK',
    detail: `${command} ${parsed ? parsed.label : '(detected)'} is locally visible and satisfies every applicable documented floor`,
    installed: true,
    version: parsed ? parsed.label : null,
  };
}

function runCli(argv) {
  const command = argv[0];
  const toolArg = argv.find((arg) => arg.startsWith('--tool='));
  const tool = toolArg ? toolArg.slice('--tool='.length) : null;
  const json = argv.includes('--json');
  if (tool && !TOOLS.includes(tool)) {
    process.stderr.write(`runtime-contract: unknown adapter '${tool}' (one of: ${TOOLS.join(', ')})\n`);
    return 2;
  }

  if (command === 'validate') {
    const selected = tool ? [tool] : TOOLS;
    let failed = false;
    const reports = selected.map((name) => {
      let problems;
      try { problems = validateRuntimeContract(loadMetadata(name)); }
      catch (error) { problems = [error.message]; }
      if (problems.length) failed = true;
      return { tool: name, problems };
    });
    if (json) process.stdout.write(`${JSON.stringify(reports, null, 2)}\n`);
    else {
      for (const report of reports) {
        if (report.problems.length) {
          for (const problem of report.problems) process.stdout.write(`FAIL ${report.tool} — ${problem}\n`);
        } else process.stdout.write(`OK   ${report.tool} — runtime contract valid\n`);
      }
    }
    return failed ? 1 : 0;
  }

  if (command === 'inspect') {
    const selected = tool ? [tool] : TOOLS;
    const reports = selected.map((name) => inspectRuntime(name));
    if (json) process.stdout.write(`${JSON.stringify(reports, null, 2)}\n`);
    else {
      for (const report of reports) {
        process.stdout.write(`${report.severity.padEnd(4)} ${report.tool} [${report.status}] — ${report.detail}\n`);
      }
    }
    return reports.some((report) => report.severity === 'FAIL') ? 2
      : reports.some((report) => report.severity === 'WARN') ? 1 : 0;
  }

  process.stderr.write('Usage: node bin/runtime-contract.js validate|inspect [--tool=<adapter>] [--json]\n');
  return 2;
}

if (require.main === module) process.exitCode = runCli(process.argv.slice(2));

module.exports = {
  TOOLS,
  inspectRuntime,
  loadMetadata,
  parseVersion,
  validateRuntimeContract,
  versionProbeEnv,
  versionAtLeast,
};
