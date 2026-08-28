#!/usr/bin/env node
'use strict';

/*
 * Read-only isolated-workspace bootstrap contract (ADR-078).
 *
 * This module validates and renders a plan. It deliberately has no copy,
 * command-execution, cleanup, network, or secret-resolution code path.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { validateRelative } = require('./path-safety.js');

const SCHEMA_VERSION = 1;
const MANIFEST_REL = '.conductor/bootstrap.json';
const MANIFEST_LIMIT = 64 * 1024;
const COPY_FILE_LIMIT = 1024 * 1024;
const ROOT_KEYS = new Set(['schema_version', 'copy_allowlist', 'setup_steps']);
const STEP_KEYS = new Set(['id', 'cwd', 'argv']);
const ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,79}$/;
const SHELL_EXECUTABLES = new Set([
  'sh', 'sh.exe', 'bash', 'bash.exe', 'zsh', 'zsh.exe', 'fish', 'fish.exe',
  'cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe',
  'wsl', 'wsl.exe',
]);
const INDIRECT_EXECUTABLES = new Set(['env', 'env.exe', 'xargs', 'xargs.exe', 'busybox', 'busybox.exe']);

function unknownKeys(value, allowed, label) {
  const unknown = Object.keys(value).filter((key) => !allowed.has(key));
  if (unknown.length) throw new Error(`${label} contains unknown field(s): ${unknown.join(', ')}`);
}

function safeDirectory(directory, label) {
  const requested = path.resolve(directory);
  let stat;
  try { stat = fs.lstatSync(requested); }
  catch (error) {
    if (error.code === 'ENOENT') throw new Error(`${label} does not exist: ${requested}`);
    throw error;
  }
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`${label} must be a real directory, not a symlink or special file: ${requested}`);
  }
  return fs.realpathSync.native ? fs.realpathSync.native(requested) : fs.realpathSync(requested);
}

function inspectRelative(root, relative, label) {
  let current = root;
  const parts = relative === '.' ? [] : relative.split('/');
  for (let index = 0; index < parts.length; index += 1) {
    current = path.join(current, parts[index]);
    let stat;
    try { stat = fs.lstatSync(current); }
    catch (error) {
      if (error.code === 'ENOENT') return { exists: false, absolute: current, missing_index: index };
      throw error;
    }
    const shown = parts.slice(0, index + 1).join('/');
    if (stat.isSymbolicLink()) throw new Error(`${label} contains a symbolic link: ${shown}`);
    if (index < parts.length - 1 && !stat.isDirectory()) {
      throw new Error(`${label} ancestor is not a directory: ${shown}`);
    }
    if (index === parts.length - 1) return { exists: true, absolute: current, stat };
  }
  return { exists: true, absolute: root, stat: fs.lstatSync(root) };
}

function safePortablePath(value, label, { allowDot = false } = {}) {
  if (value === '.' && allowDot) return value;
  if (typeof value !== 'string' || value.length > 500) {
    throw new Error(`${label} must be a portable relative path up to 500 characters`);
  }
  return validateRelative(value, label);
}

function secretPathReason(relative) {
  const lower = relative.toLowerCase();
  const parts = lower.split('/');
  const base = parts[parts.length - 1];
  if (parts.some((part) => ['.git', '.hg', '.svn', '.conductor'].includes(part))) {
    return 'repository and CONDUCTOR control metadata are never eligible for bootstrap copy';
  }
  if (parts.some((part) => part === '.env' || part.startsWith('.env.'))) return '.env files are never eligible for bootstrap copy';
  if (parts.some((part) => ['.ssh', '.aws', '.azure', '.gnupg'].includes(part))) return 'credential directories are never eligible for bootstrap copy';
  if (parts.includes('.kube') && base === 'config') return 'Kubernetes credentials are never eligible for bootstrap copy';
  if (parts.includes('.docker') && base === 'config.json') return 'Docker credentials are never eligible for bootstrap copy';
  if (['.npmrc', '.pypirc', '.netrc', '.git-credentials', 'credentials', 'credentials.json', 'application_default_credentials.json'].includes(base)) {
    return 'credential-bearing configuration is never eligible for bootstrap copy';
  }
  if (/^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$/.test(base) || /\.(pem|key|p12|pfx|jks|keystore)$/.test(base)) {
    return 'private-key material is never eligible for bootstrap copy';
  }
  if (/(^|[._-])(secret|secrets|credential|credentials|api[_-]?key|access[_-]?token|refresh[_-]?token)([._-]|$)/.test(base)) {
    return 'secret- or credential-named files are never eligible for bootstrap copy';
  }
  if (/^service[-_.]?account.*\.json$/.test(base)) return 'service-account credentials are never eligible for bootstrap copy';
  return null;
}

function placeholder(value) {
  return !value
    || /^\$\{?[A-Z][A-Z0-9_]*\}?$/.test(value)
    || /^<[^>]+>$/.test(value)
    || /^(?:env:|process\.env\.)/i.test(value);
}

function containsLiteralCredentialUrl(value) {
  const pattern = /\b[a-z][a-z0-9+.-]*:\/\/([^\s/:@]+):([^\s/@]+)@/gi;
  let match;
  while ((match = pattern.exec(value)) !== null) {
    if (!placeholder(match[2])) return true;
  }
  return false;
}

function credentialLikeText(buffer) {
  if (buffer.includes(0)) return 'binary or opaque files are not eligible for bootstrap copy';
  const text = buffer.toString('utf8');
  if (/-----BEGIN (?:RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text)) return 'private-key content detected';
  if (/\bAKIA[0-9A-Z]{16}\b/.test(text)
      || /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[0-9A-Za-z-]{20,}|sk-[A-Za-z0-9_-]{20,})\b/.test(text)) {
    return 'credential-shaped literal detected';
  }
  if (containsLiteralCredentialUrl(text)) return 'credential-bearing URL detected';
  const assignment = /(?:^|[\s"'])(?:api[_-]?key|token|secret|password|authorization|bearer|private[_-]?key|client[_-]?secret)["']?\s*[:=]\s*["']?([^\s"',}]+)/gim;
  let match;
  while ((match = assignment.exec(text)) !== null) {
    if (!placeholder(match[1])) return 'credential-like assignment contains a literal value';
  }
  return null;
}

function argvSecretReason(argument) {
  if (/-----BEGIN (?:RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----/.test(argument)) return 'private-key content';
  if (/\bAKIA[0-9A-Z]{16}\b/.test(argument)
      || /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[0-9A-Za-z-]{20,}|sk-[A-Za-z0-9_-]{20,})\b/.test(argument)) {
    return 'credential-shaped literal';
  }
  if (containsLiteralCredentialUrl(argument)) return 'credential-bearing URL';
  const match = argument.match(/(?:^|--?)(?:api[_-]?key|token|secret|password|authorization|bearer|private[_-]?key|client[_-]?secret)[:=](.+)$/i);
  if (match && !placeholder(match[1])) return 'literal credential argument';
  return null;
}

function portableExecutableName(value) {
  return value.split(/[\\/]/).pop().toLowerCase();
}

function interpreterEvalReason(executable, argv) {
  const args = argv.slice(1);
  if (/^(?:node|nodejs|bun)(?:\.exe)?$/.test(executable)
      && args.some((argument) => argument.startsWith('-e') || argument.startsWith('-p')
        || argument === '--eval' || argument === '--print' || argument.startsWith('--eval='))) {
    return 'JavaScript evaluation flags';
  }
  if (/^deno(?:\.exe)?$/.test(executable) && args.includes('eval')) return 'Deno eval subcommand';
  if (/^python(?:\d+(?:\.\d+)*)?(?:\.exe)?$/.test(executable)
      && args.some((argument) => argument.startsWith('-c'))) {
    return 'Python evaluation flags';
  }
  if (/^(?:perl|ruby)(?:\.exe)?$/.test(executable)
      && args.some((argument) => argument.startsWith('-e'))) {
    return 'interpreter evaluation flags';
  }
  if (/^php(?:\.exe)?$/.test(executable)
      && args.some((argument) => argument.startsWith('-r'))) {
    return 'PHP evaluation flags';
  }
  return null;
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function load(targetDir) {
  const target = safeDirectory(targetDir || '.', 'bootstrap target');
  const conductorPath = inspectRelative(target, '.conductor', 'bootstrap manifest path');
  if (!conductorPath.exists || !conductorPath.stat.isDirectory()) {
    throw new Error(`bootstrap manifest directory is missing or not a directory: ${path.join(target, '.conductor')}`);
  }
  const manifestPath = inspectRelative(target, MANIFEST_REL, 'bootstrap manifest path');
  if (!manifestPath.exists) throw new Error(`bootstrap manifest is missing: ${path.join(target, MANIFEST_REL)}`);
  if (!manifestPath.stat.isFile() || manifestPath.stat.nlink !== 1 || manifestPath.stat.size > MANIFEST_LIMIT) {
    throw new Error(`bootstrap manifest must be a single-link regular file no larger than ${MANIFEST_LIMIT} bytes`);
  }
  let raw;
  try { raw = JSON.parse(fs.readFileSync(manifestPath.absolute, 'utf8')); }
  catch { throw new Error('bootstrap manifest is invalid JSON'); }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('bootstrap manifest root must be an object');
  unknownKeys(raw, ROOT_KEYS, 'bootstrap manifest');
  if (raw.schema_version !== SCHEMA_VERSION) throw new Error(`bootstrap schema_version must be ${SCHEMA_VERSION}`);
  if (!Array.isArray(raw.copy_allowlist) || raw.copy_allowlist.length > 128) {
    throw new Error('copy_allowlist must be an array with at most 128 paths');
  }
  const copyAllowlist = raw.copy_allowlist.map((entry, index) => {
    const relative = safePortablePath(entry, `copy_allowlist[${index}]`);
    const reason = secretPathReason(relative);
    if (reason) throw new Error(`copy_allowlist[${index}] '${relative}' refused: ${reason}`);
    return relative;
  });
  if (new Set(copyAllowlist).size !== copyAllowlist.length) throw new Error('copy_allowlist contains duplicates');

  if (!Array.isArray(raw.setup_steps) || raw.setup_steps.length > 32) {
    throw new Error('setup_steps must be an array with at most 32 entries');
  }
  const ids = new Set();
  const setupSteps = raw.setup_steps.map((step, index) => {
    if (!step || typeof step !== 'object' || Array.isArray(step)) throw new Error(`setup_steps[${index}] must be an object`);
    unknownKeys(step, STEP_KEYS, `setup_steps[${index}]`);
    if (!ID_PATTERN.test(step.id || '')) throw new Error(`setup_steps[${index}].id is invalid`);
    if (ids.has(step.id)) throw new Error(`setup_steps contains duplicate id '${step.id}'`);
    ids.add(step.id);
    const cwd = safePortablePath(step.cwd === undefined ? '.' : step.cwd, `setup_steps[${index}].cwd`, { allowDot: true });
    if (!Array.isArray(step.argv) || step.argv.length < 1 || step.argv.length > 32) {
      throw new Error(`setup_steps[${index}].argv must contain 1-32 arguments`);
    }
    let total = 0;
    const argv = step.argv.map((argument, argIndex) => {
      if (typeof argument !== 'string' || !argument || argument.length > 2048 || /[\u0000-\u001f\u007f]/u.test(argument)) {
        throw new Error(`setup_steps[${index}].argv[${argIndex}] is invalid`);
      }
      total += argument.length;
      const reason = argvSecretReason(argument);
      if (reason) throw new Error(`setup_steps[${index}].argv[${argIndex}] refused: ${reason}`);
      return argument;
    });
    if (total > 8192) throw new Error(`setup_steps[${index}].argv exceeds 8192 characters`);
    const executable = portableExecutableName(argv[0]);
    if (SHELL_EXECUTABLES.has(executable)) {
      throw new Error(`setup_steps[${index}] refuses shell interpreters; use a direct argv command for planning`);
    }
    if (INDIRECT_EXECUTABLES.has(executable)) {
      throw new Error(`setup_steps[${index}] refuses indirect command wrappers; use a direct argv command for planning`);
    }
    const evalReason = interpreterEvalReason(executable, argv);
    if (evalReason) throw new Error(`setup_steps[${index}] refuses ${evalReason}; use a script file or direct command for planning`);
    return { id: step.id, cwd, argv };
  });
  if (!copyAllowlist.length && !setupSteps.length) throw new Error('bootstrap manifest has no copy or setup actions');
  return { schema_version: SCHEMA_VERSION, target, file: manifestPath.absolute, copy_allowlist: copyAllowlist, setup_steps: setupSteps };
}

function inspect(targetDir, options = {}) {
  const contract = load(targetDir);
  let source = null;
  if (contract.copy_allowlist.length) {
    if (!options.source) throw new Error('copy_allowlist requires an explicit --source=<trusted-worktree>');
    source = safeDirectory(options.source, 'bootstrap source');
  } else if (options.source) source = safeDirectory(options.source, 'bootstrap source');

  const copyPlan = contract.copy_allowlist.map((relative) => {
    const sourceEntry = inspectRelative(source, relative, `copy source '${relative}'`);
    if (!sourceEntry.exists) throw new Error(`copy source is missing: ${relative}`);
    if (!sourceEntry.stat.isFile() || sourceEntry.stat.nlink !== 1 || sourceEntry.stat.size > COPY_FILE_LIMIT) {
      throw new Error(`copy source '${relative}' must be a single-link regular file no larger than ${COPY_FILE_LIMIT} bytes`);
    }
    const sourceBytes = fs.readFileSync(sourceEntry.absolute);
    const reason = credentialLikeText(sourceBytes);
    if (reason) throw new Error(`copy source '${relative}' refused: ${reason}; no value was returned`);

    const destination = inspectRelative(contract.target, relative, `copy destination '${relative}'`);
    let status = 'would-copy';
    if (destination.exists) {
      if (!destination.stat.isFile() || destination.stat.nlink !== 1) {
        throw new Error(`copy destination '${relative}' must be absent or a single-link regular file`);
      }
      const destinationBytes = fs.readFileSync(destination.absolute);
      if (!sourceBytes.equals(destinationBytes)) {
        throw new Error(`copy destination '${relative}' already exists with different content; overwrite is not allowed`);
      }
      status = 'already-present';
    }
    return { path: relative, status, bytes: sourceBytes.length, sha256: sha256(sourceBytes) };
  });

  const setupPlan = contract.setup_steps.map((step) => {
    const cwd = inspectRelative(contract.target, step.cwd, `setup cwd '${step.cwd}'`);
    if (!cwd.exists || !cwd.stat.isDirectory()) throw new Error(`setup cwd must be an existing real directory: ${step.cwd}`);
    return { ...step, status: 'inert-preview-only' };
  });

  return {
    schema_version: SCHEMA_VERSION,
    manifest: contract.file,
    source,
    target: contract.target,
    read_only: true,
    dry_run: true,
    files_copied: false,
    commands_executed: false,
    known_secret_values_included: false,
    summary: {
      copy_entries: copyPlan.length,
      would_copy: copyPlan.filter((entry) => entry.status === 'would-copy').length,
      already_present: copyPlan.filter((entry) => entry.status === 'already-present').length,
      setup_steps: setupPlan.length,
    },
    copy_plan: copyPlan,
    setup_plan: setupPlan,
  };
}

function renderCheck(report) {
  return [
    `CONDUCTOR workspace bootstrap check (read-only): ${report.target}`,
    `OK — ${report.summary.copy_entries} copy allowlist item(s), ${report.summary.setup_steps} inert setup step(s).`,
    'No files were copied, no commands were executed, and no known secret values were accepted.',
  ].join('\n');
}

function renderPlan(report) {
  const lines = [
    `CONDUCTOR workspace bootstrap plan (dry-run only): ${report.target}`,
    `Source: ${report.source || '(none — no copy entries)'}`,
  ];
  for (const entry of report.copy_plan) {
    lines.push(`  ${entry.status === 'would-copy' ? 'COPY' : 'PRESENT'} ${entry.path} (${entry.bytes} bytes, sha256:${entry.sha256.slice(0, 12)})`);
  }
  for (const step of report.setup_plan) {
    lines.push(`  SETUP [${step.id}] cwd=${step.cwd} argv=${step.argv.map((arg) => JSON.stringify(arg)).join(' ')}`);
  }
  lines.push('DRY-RUN ONLY — no files copied, no commands executed, no cleanup performed.');
  return lines.join('\n');
}

module.exports = {
  COPY_FILE_LIMIT,
  MANIFEST_REL,
  SCHEMA_VERSION,
  inspect,
  load,
  renderCheck,
  renderPlan,
  secretPathReason,
};
