'use strict';

const fs = require('fs');
const path = require('path');

const COMMON = [
  '.conductor',
  'docs/CURRENT_WORK.md', 'docs/REMAINING_TASKS.md', 'docs/PLANS.md',
  'docs/TASKS.md', 'docs/INDEX.md', 'docs/specs/_example.md',
  '.conductor-manifest.json',
];
const MANAGED = {
  claude: ['CLAUDE.md', '.claude/rules', '.claude/agents', '.claude/hooks', '.claude/commands', '.claude/settings.json'],
  cursor: ['.cursorrules', '.cursor/rules', '.cursor/agents', '.cursor/skills', '.cursor/hooks.json'],
  copilot: ['.github/copilot-instructions.md', '.github/instructions', '.github/agents', '.github/hooks', '.github/prompts'],
  gemini: ['GEMINI.md', '.gemini/styleguide.md', '.gemini/agents', '.gemini/commands', '.gemini/settings.json'],
  codex: ['AGENTS.md', '.codex/conductor', '.codex/agents', '.codex/hooks', '.codex/hooks.json', '.agents/skills'],
  windsurf: ['.windsurfrules', '.windsurf/workflows', '.windsurf/hooks', '.windsurf/hooks.json', '.devin/rules'],
};
const COMMON_MANIFEST_FILES = new Set([
  'docs/CURRENT_WORK.md', 'docs/REMAINING_TASKS.md', 'docs/PLANS.md',
  'docs/TASKS.md', 'docs/INDEX.md', 'docs/specs/_example.md',
  '.conductor/project.json', '.conductor/trajectories/.gitignore',
]);
const MANIFEST_DIRS = {
  claude: ['.claude/rules', '.claude/agents', '.claude/hooks', '.claude/commands'],
  cursor: ['.cursor/rules', '.cursor/agents', '.cursor/skills'],
  copilot: ['.github/instructions', '.github/agents', '.github/hooks', '.github/prompts'],
  gemini: ['.gemini/agents', '.gemini/commands'],
  codex: ['.codex/conductor', '.codex/agents', '.codex/hooks', '.agents/skills'],
  windsurf: ['.windsurf/workflows', '.windsurf/hooks', '.devin/rules'],
};

function isInside(root, candidate) {
  return candidate !== root && candidate.startsWith(root + path.sep);
}

function validateRelative(rel, label = 'path') {
  if (typeof rel !== 'string' || !rel || rel.includes('\\') || /[\u0000-\u001f\u007f]/u.test(rel)) {
    throw new Error(`${label} must be a non-empty portable relative path`);
  }
  if (path.isAbsolute(rel)) throw new Error(`${label} must not be absolute: ${rel}`);
  const parts = rel.split('/');
  if (parts.some((part) => !part || part === '.' || part === '..')) throw new Error(`${label} contains an unsafe segment: ${rel}`);
  return rel;
}

function manifestPathAllowed(adapter, rel) {
  if (COMMON_MANIFEST_FILES.has(rel) || rel.startsWith('.conductor/reflect/')) return true;
  if (adapter === 'claude' && rel === '.claude/settings.json') return true;
  if ((MANAGED[adapter] || []).includes(rel)) return true;
  if ((MANIFEST_DIRS[adapter] || []).some((dir) => rel.startsWith(`${dir}/`))) return true;
  if (adapter === 'claude' && /^\.claude\/hookify\.[A-Za-z0-9._-]+\.local\.md$/.test(rel)) return true;
  return false;
}

function inspectExisting(abs, label) {
  const stat = fs.lstatSync(abs);
  if (stat.isSymbolicLink()) throw new Error(`${label} is a symbolic link: ${abs}`);
  if (stat.isFile() && stat.nlink !== 1) throw new Error(`${label} is hard-linked: ${abs}`);
  if (!stat.isFile() && !stat.isDirectory()) throw new Error(`${label} is a special file: ${abs}`);
  return stat;
}

function inspectPath(root, rel, walkFinalDirectory = true) {
  validateRelative(rel, 'managed path');
  let current = root;
  const parts = rel.split('/');
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    let exists = true;
    try { fs.lstatSync(current); } catch (error) { if (error.code === 'ENOENT') exists = false; else throw error; }
    if (!exists) continue;
    const stat = inspectExisting(current, `managed path component '${parts.slice(0, i + 1).join('/')}'`);
    if (i < parts.length - 1 && !stat.isDirectory()) throw new Error(`managed path ancestor is not a directory: ${current}`);
    if (i === parts.length - 1 && walkFinalDirectory && stat.isDirectory()) {
      const stack = [current];
      while (stack.length) {
        const dir = stack.pop();
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const child = path.join(dir, entry.name);
          const childStat = inspectExisting(child, 'managed subtree entry');
          if (childStat.isDirectory()) stack.push(child);
        }
      }
    }
  }
}

function assertSafeManagedPaths(targetDir, tools) {
  const requested = path.resolve(targetDir);
  const targetStat = fs.lstatSync(requested);
  if (targetStat.isSymbolicLink()) throw new Error(`target directory must not be a symbolic link: ${requested}`);
  if (!targetStat.isDirectory()) throw new Error(`target is not a directory: ${requested}`);
  const root = fs.realpathSync(requested);
  const selected = [...new Set(tools)];
  for (const tool of selected) {
    if (!MANAGED[tool]) throw new Error(`unknown adapter '${tool}'`);
  }
  const paths = [...COMMON, ...selected.flatMap((tool) => MANAGED[tool])];
  for (const rel of new Set(paths)) inspectPath(root, rel);
  if (selected.includes('claude')) {
    const claudeRoot = path.join(root, '.claude');
    try {
      for (const name of fs.readdirSync(claudeRoot)) {
        if (/^hookify\.[A-Za-z0-9._-]+\.local\.md$/.test(name)) inspectPath(root, `.claude/${name}`);
      }
    } catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error; }
  }
  return root;
}

function validateManifest(manifestPath, targetDir, expectedAdapter, options = {}) {
  const root = fs.realpathSync(targetDir);
  const manifestAbs = fs.realpathSync(path.resolve(manifestPath));
  if (!isInside(root, manifestAbs)) throw new Error(`manifest escapes target: ${manifestAbs}`);
  inspectPath(root, path.relative(root, manifestAbs).split(path.sep).join('/'), false);
  let manifest;
  try { manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
  catch (error) { throw new Error(`manifest is invalid JSON: ${error.message}`); }
  const legacy = options.allowLegacy === true;
  if (!manifest || (!legacy && (manifest.schema_version !== 2 || manifest.manifest_scope !== 'adapter'))) {
    throw new Error('manifest is not adapter-scoped schema v2');
  }
  if (manifest.adapter !== undefined && manifest.adapter !== expectedAdapter) throw new Error(`manifest adapter '${manifest.adapter}' does not match '${expectedAdapter}'`);
  if (!legacy && manifest.adapter !== expectedAdapter) throw new Error(`manifest adapter '${manifest.adapter}' does not match '${expectedAdapter}'`);
  if (!Array.isArray(manifest.emitted_files)) throw new Error('manifest emitted_files must be an array');
  const seen = new Set();
  for (const [index, entry] of manifest.emitted_files.entries()) {
    if (!entry || typeof entry !== 'object') throw new Error(`manifest entry ${index} is invalid`);
    const rel = validateRelative(entry.path, `manifest entry ${index} path`);
    if (!manifestPathAllowed(expectedAdapter, rel)) throw new Error(`manifest entry ${index} is outside the ${expectedAdapter} managed surface: ${rel}`);
    const ownershipKey = `${rel}\u0000${entry.type === 'block' ? String(entry.block || '') : '<file>'}`;
    if (seen.has(ownershipKey)) throw new Error(`manifest contains duplicate ownership: ${rel}`);
    seen.add(ownershipKey);
    const resolved = path.resolve(root, rel);
    if (!isInside(root, resolved)) throw new Error(`manifest entry ${index} escapes target: ${rel}`);
    inspectPath(root, rel, false);
    if (entry.backup_path) {
      const backup = validateRelative(entry.backup_path, `manifest entry ${index} backup_path`);
      const backupResolved = path.resolve(root, backup);
      if (!isInside(root, backupResolved)) throw new Error(`manifest backup escapes target: ${backup}`);
      if (!backup.startsWith(`${rel}.conductor-backup-`)) throw new Error(`manifest backup is not owned by its path: ${backup}`);
      inspectPath(root, backup, false);
    }
    if (entry.type === 'block' && (typeof entry.block !== 'string' || !/^[A-Za-z0-9._-]+$/.test(entry.block))) {
      throw new Error(`manifest entry ${index} has an invalid block name`);
    }
    if (entry.type !== undefined && entry.type !== 'file' && entry.type !== 'block') {
      throw new Error(`manifest entry ${index} has an invalid type`);
    }
    if (typeof entry.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(entry.sha256)) {
      throw new Error(`manifest entry ${index} has an invalid sha256`);
    }
  }
  return manifest;
}

if (require.main === module) {
  try {
    if (process.argv[2] === '--manifest') validateManifest(process.argv[3], process.argv[4], process.argv[5]);
    else if (process.argv[2] === '--legacy-manifest') validateManifest(process.argv[3], process.argv[4], process.argv[5], { allowLegacy: true });
    else assertSafeManagedPaths(process.argv[3], [process.argv[2]]);
  } catch (error) {
    process.stderr.write(`CONDUCTOR path safety: ${error.message}\n`);
    process.exit(2);
  }
}

module.exports = { MANAGED, assertSafeManagedPaths, validateManifest, validateRelative };
