#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const workContract = require('./work-contract.js');

const SCHEMA_VERSION = 1;
const MANIFEST_REL = '.conductor/workspace.json';
const MANIFEST_LIMIT = 256 * 1024;
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode'];
const ROOT_KEYS = new Set(['schema_version', 'workspace_id', 'repositories']);
const REPO_KEYS = new Set(['id', 'path', 'depends_on', 'write_scopes', 'target_branch', 'required_adapters']);
const ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,79}$/;
const BRANCH_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/;

function safeDirectory(directory, label) {
  const stat = fs.lstatSync(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`${label} must be a real directory: ${directory}`);
  return fs.realpathSync(directory);
}

function safeFile(file, label, limit = MANIFEST_LIMIT) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > limit) {
    throw new Error(`${label} must be a single-link regular file no larger than ${limit} bytes`);
  }
  return stat;
}

function inspectRelativeDirectoryPath(root, relative, label) {
  let current = root;
  for (const segment of relative.split('/').filter((item) => item && item !== '.')) {
    current = path.join(current, segment);
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error(`${label} contains a non-directory or symbolic-link component: ${current}`);
    }
  }
}

function unknownKeys(value, allowed, label) {
  const unknown = Object.keys(value).filter((key) => !allowed.has(key));
  if (unknown.length) throw new Error(`${label} contains unknown field(s): ${unknown.join(', ')}`);
}

function safeRelative(value, label) {
  if (typeof value !== 'string' || !value || value.length > 300 || value.includes('\0')) {
    throw new Error(`${label} must be a non-empty relative path up to 300 characters`);
  }
  const slash = value.replace(/\\/g, '/').replace(/^\.\//, '').replace(/\/+$/, '') || '.';
  if (slash.startsWith('/') || /^[A-Za-z]:\//.test(slash)) throw new Error(`${label} must be relative`);
  const normalized = path.posix.normalize(slash);
  if (normalized === '..' || normalized.startsWith('../') || normalized.includes('/../')) throw new Error(`${label} escapes the workspace`);
  return normalized;
}

function stringArray(value, label, options = {}) {
  if (value === undefined) return options.defaultValue || [];
  if (!Array.isArray(value) || value.length > (options.max || 64)) throw new Error(`${label} must be a bounded array`);
  const output = value.map((item) => {
    if (typeof item !== 'string' || !item || item.length > 300) throw new Error(`${label} contains an invalid string`);
    return item;
  });
  if (new Set(output).size !== output.length) throw new Error(`${label} contains duplicates`);
  return output;
}

function load(targetDir) {
  const requested = path.resolve(targetDir || '.');
  const root = safeDirectory(requested, 'workspace root');
  const file = path.join(root, MANIFEST_REL);
  if (!fs.existsSync(file)) throw new Error(`workspace manifest is missing: ${file}`);
  inspectRelativeDirectoryPath(root, '.conductor', 'workspace manifest path');
  safeFile(file, 'workspace manifest');
  let raw;
  try { raw = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error('workspace manifest is invalid JSON'); }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('workspace manifest root must be an object');
  unknownKeys(raw, ROOT_KEYS, 'workspace manifest');
  if (raw.schema_version !== SCHEMA_VERSION) throw new Error(`workspace schema_version must be ${SCHEMA_VERSION}`);
  if (!ID_PATTERN.test(raw.workspace_id || '')) throw new Error('workspace_id is invalid');
  if (!Array.isArray(raw.repositories) || raw.repositories.length < 1 || raw.repositories.length > 32) {
    throw new Error('repositories must contain 1-32 entries');
  }

  const ids = new Set();
  const roots = new Set();
  const repositories = raw.repositories.map((entry, index) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error(`repository ${index} must be an object`);
    unknownKeys(entry, REPO_KEYS, `repository ${index}`);
    if (!ID_PATTERN.test(entry.id || '')) throw new Error(`repository ${index} id is invalid`);
    if (ids.has(entry.id)) throw new Error(`duplicate repository id '${entry.id}'`);
    ids.add(entry.id);
    const relative = safeRelative(entry.path, `repository ${entry.id} path`);
    const absolute = path.resolve(root, relative);
    if (absolute !== root && !absolute.startsWith(`${root}${path.sep}`)) throw new Error(`repository ${entry.id} escapes the workspace`);
    if (relative !== '.') inspectRelativeDirectoryPath(root, relative, `repository ${entry.id} path`);
    const canonical = safeDirectory(absolute, `repository ${entry.id}`);
    if (canonical !== root && !canonical.startsWith(`${root}${path.sep}`)) throw new Error(`repository ${entry.id} resolves outside the workspace`);
    if (roots.has(canonical)) throw new Error(`duplicate canonical repository root: ${canonical}`);
    roots.add(canonical);
    const dependsOn = stringArray(entry.depends_on, `repository ${entry.id} depends_on`, { max: 31 });
    const writeScopes = stringArray(entry.write_scopes, `repository ${entry.id} write_scopes`, { defaultValue: ['.'] })
      .map((scope) => safeRelative(scope, `repository ${entry.id} write scope`));
    const requiredAdapters = stringArray(entry.required_adapters, `repository ${entry.id} required_adapters`, { max: TOOLS.length });
    for (const tool of requiredAdapters) if (!TOOLS.includes(tool)) throw new Error(`repository ${entry.id} has unknown required adapter '${tool}'`);
    const targetBranch = entry.target_branch === undefined ? null : entry.target_branch;
    if (targetBranch !== null && !BRANCH_PATTERN.test(targetBranch)) throw new Error(`repository ${entry.id} target_branch is invalid`);
    return {
      id: entry.id,
      path: relative,
      root: canonical,
      depends_on: [...dependsOn].sort(),
      write_scopes: [...new Set(writeScopes)].sort(),
      target_branch: targetBranch,
      required_adapters: [...requiredAdapters].sort(),
    };
  });

  for (const repo of repositories) {
    for (const dependency of repo.depends_on) {
      if (!ids.has(dependency)) throw new Error(`repository ${repo.id} depends on unknown repository '${dependency}'`);
      if (dependency === repo.id) throw new Error(`repository ${repo.id} cannot depend on itself`);
    }
  }
  const visiting = new Set();
  const visited = new Set();
  const order = [];
  const byId = new Map(repositories.map((repo) => [repo.id, repo]));
  function visit(id, stack) {
    if (visiting.has(id)) throw new Error(`repository dependency cycle: ${[...stack, id].join(' -> ')}`);
    if (visited.has(id)) return;
    visiting.add(id);
    const repo = byId.get(id);
    for (const dependency of [...repo.depends_on].sort()) visit(dependency, [...stack, id]);
    visiting.delete(id);
    visited.add(id);
    order.push(id);
  }
  for (const id of [...ids].sort()) visit(id, []);
  return { schema_version: SCHEMA_VERSION, workspace_id: raw.workspace_id, root, file, repositories, order };
}

function installedPolicy(repoRoot) {
  const dir = path.join(repoRoot, '.conductor', 'manifests');
  if (!fs.existsSync(dir)) return { adapters: [], versions: [] };
  inspectRelativeDirectoryPath(repoRoot, '.conductor/manifests', 'adapter manifest path');
  safeDirectory(dir, 'adapter manifest directory');
  const adapters = [];
  const versions = [];
  for (const name of fs.readdirSync(dir).sort()) {
    if (!name.endsWith('.json')) throw new Error(`unexpected adapter manifest entry: ${name}`);
    const tool = name.slice(0, -5);
    if (!TOOLS.includes(tool)) throw new Error(`unknown adapter manifest '${name}'`);
    const file = path.join(dir, name);
    safeFile(file, `${tool} adapter manifest`, 2 * 1024 * 1024);
    let manifest;
    try { manifest = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch { throw new Error(`${tool} adapter manifest is invalid JSON`); }
    if (manifest.schema_version !== 2 || manifest.manifest_scope !== 'adapter' || manifest.adapter !== tool) {
      throw new Error(`${tool} adapter manifest has an invalid identity contract`);
    }
    if (typeof manifest.version !== 'string' || !manifest.version) throw new Error(`${tool} adapter manifest has no version`);
    adapters.push(tool);
    versions.push(manifest.version.replace(/^v/, ''));
  }
  return { adapters, versions: [...new Set(versions)].sort() };
}

function inspect(targetDir) {
  const workspace = load(targetDir);
  const checks = [];
  const add = (id, status, detail) => checks.push({ id, status, detail });
  const repositories = [];
  const allVersions = new Set();

  for (const id of workspace.order) {
    const config = workspace.repositories.find((repo) => repo.id === id);
    let snapshot;
    try {
      const resolved = workContract.resolveRepository(config.root);
      if (resolved.top !== config.root) throw new Error(`declared path is inside Git root ${resolved.top}, not an exact repository root`);
      snapshot = workContract.snapshot(config.root);
    } catch (error) {
      add(`repo:${id}`, 'FAIL', error.message);
      repositories.push({ id, path: config.path, root: config.root, error: error.message });
      continue;
    }
    let policy;
    try { policy = installedPolicy(config.root); }
    catch (error) {
      add(`policy:${id}`, 'FAIL', error.message);
      policy = { adapters: [], versions: [] };
    }
    for (const version of policy.versions) allVersions.add(version);
    const missing = config.required_adapters.filter((tool) => !policy.adapters.includes(tool));
    if (missing.length) add(`policy:${id}`, 'FAIL', `required adapter(s) missing: ${missing.join(', ')}`);
    else add(`policy:${id}`, 'OK', `${policy.adapters.length} installed adapter(s)${policy.versions.length ? ` at ${policy.versions.join(', ')}` : ''}`);
    if (config.target_branch && snapshot.branch !== config.target_branch) {
      add(`branch:${id}`, 'WARN', `current branch '${snapshot.branch}' differs from target '${config.target_branch}'`);
    } else add(`branch:${id}`, 'OK', `branch ${snapshot.branch}${config.target_branch ? ' matches target' : ''}`);
    add(`snapshot:${id}`, 'OK', `${snapshot.head.slice(0, 12)} · ${snapshot.dirty ? `${snapshot.changed_entries} changed entr${snapshot.changed_entries === 1 ? 'y' : 'ies'}` : 'clean'}`);
    repositories.push({
      id,
      path: config.path,
      root: config.root,
      depends_on: config.depends_on,
      write_scopes: config.write_scopes,
      target_branch: config.target_branch,
      required_adapters: config.required_adapters,
      snapshot,
      policy,
      current_work: fs.existsSync(path.join(config.root, 'docs', 'CURRENT_WORK.md'))
        ? 'docs/CURRENT_WORK.md'
        : fs.existsSync(path.join(config.root, 'CURRENT_WORK.md')) ? 'CURRENT_WORK.md' : null,
    });
  }
  if (allVersions.size > 1) add('workspace:policy-drift', 'WARN', `CONDUCTOR policy versions differ: ${[...allVersions].sort().join(', ')}`);
  else add('workspace:policy-drift', 'OK', allVersions.size ? `CONDUCTOR policy version ${[...allVersions][0]}` : 'no installed policy versions to compare');

  const digest = crypto.createHash('sha256');
  digest.update(`workspace-v1\0${workspace.workspace_id}\0`);
  for (const repo of [...repositories].sort((a, b) => a.id.localeCompare(b.id))) {
    digest.update(`${repo.id}\0${repo.path}\0`);
    digest.update(`depends\0${(repo.depends_on || []).join(',')}\0`);
    digest.update(`scopes\0${(repo.write_scopes || []).join(',')}\0`);
    digest.update(`target\0${repo.target_branch || ''}\0`);
    digest.update(`required\0${(repo.required_adapters || []).join(',')}\0`);
    if (repo.snapshot) digest.update(`${repo.snapshot.head}\0${repo.snapshot.digest}\0`);
    else digest.update(`error\0${repo.error}\0`);
    if (repo.policy) digest.update(`${repo.policy.adapters.join(',')}\0${repo.policy.versions.join(',')}\0`);
  }
  const counts = { OK: 0, WARN: 0, FAIL: 0 };
  for (const check of checks) counts[check.status] += 1;
  return {
    schema_version: SCHEMA_VERSION,
    workspace_id: workspace.workspace_id,
    workspace_root: workspace.root,
    manifest: MANIFEST_REL.split(path.sep).join('/'),
    dependency_order: workspace.order,
    change_set_digest: digest.digest('hex'),
    repositories,
    checks,
    summary: counts,
  };
}

function render(report) {
  const lines = [`Workspace ${report.workspace_id} · ${report.change_set_digest.slice(0, 16)}`];
  for (const repo of report.repositories) {
    if (repo.error) lines.push(`  ${repo.id}: FAIL · ${repo.error}`);
    else lines.push(`  ${repo.id}: ${repo.snapshot.branch}@${repo.snapshot.head.slice(0, 12)} · ${repo.snapshot.dirty ? 'dirty' : 'clean'} · adapters=${repo.policy.adapters.join(',') || 'none'}`);
  }
  for (const check of report.checks.filter((item) => item.status !== 'OK')) lines.push(`  ${check.status} [${check.id}] ${check.detail}`);
  lines.push(`Summary: ${report.summary.OK} ok, ${report.summary.WARN} warn, ${report.summary.FAIL} fail`);
  return lines.join('\n');
}

module.exports = { MANIFEST_REL, inspect, load, render };
