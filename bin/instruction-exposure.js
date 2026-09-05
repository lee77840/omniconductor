'use strict';

// A bounded, local-only lower bound. Native global settings and model-visible
// skill catalogs are deliberately not guessed or fetched.
const fs = require('fs');
const path = require('path');

function inspect(target, adapter, managed) {
  const files = new Set();
  const warnings = [];
  const unresolved = [];
  function safe(relative) {
    if (typeof relative !== 'string' || !relative || path.isAbsolute(relative)
      || relative.includes('\\') || relative.split('/').some(x => x === '..' || x === '.')) return false;
    let cursor = target;
    for (const part of relative.split('/')) {
      cursor = path.join(cursor, part);
      if (!fs.existsSync(cursor) || fs.lstatSync(cursor).isSymbolicLink()) return false;
    }
    const s = fs.lstatSync(cursor);
    return s.isFile() && s.nlink === 1;
  }
  function add(relative) { if (safe(relative)) files.add(relative); }
  function body(relative) {
    if (!safe(relative)) return '';
    const file = path.join(target, relative);
    if (fs.statSync(file).size > 2 * 1024 * 1024) { unresolved.push(`${relative}: too large to parse`); return ''; }
    return fs.readFileSync(file, 'utf8');
  }
  function directory(relative, accept) {
    const full = path.join(target, relative);
    if (!fs.existsSync(full) || fs.lstatSync(full).isSymbolicLink() || !fs.statSync(full).isDirectory()) return;
    const names = fs.readdirSync(full);
    if (names.length > 512) unresolved.push(`${relative}: directory exceeds 512-entry inspection limit`);
    for (const name of names.slice(0, 512)) {
      const file = `${relative}/${name}`;
      if (safe(file) && accept(body(file), name)) add(file);
    }
  }
  for (const file of managed) add(path.relative(target, file).split(path.sep).join('/'));
  if (adapter === 'claude') {
    add('CLAUDE.md'); add('.claude/CLAUDE.md'); add('CLAUDE.local.md');
    directory('.claude/rules', (s, n) => n.endsWith('.md') && !/^---\s*\n[\s\S]*?\bpaths\s*:/.test(s));
  } else if (adapter === 'codex') {
    if (safe('AGENTS.override.md')) { files.delete('AGENTS.md'); add('AGENTS.override.md'); }
    else add('AGENTS.md');
  } else if (adapter === 'windsurf') {
    add('AGENTS.md'); add('.windsurfrules');
    for (const root of ['.devin/rules', '.windsurf/rules']) directory(root,
      (s, n) => n.endsWith('.md') && /^(?:trigger|activation_mode):\s*["']?always_on["']?\s*$/m.test(s));
  } else if (adapter === 'opencode') {
    if (safe('AGENTS.md')) add('AGENTS.md'); else add('CLAUDE.md');
    if (fs.existsSync(path.join(target, 'opencode.jsonc'))) unresolved.push('opencode.jsonc: commented config requires native resolution');
    const raw = body('opencode.json');
    if (raw) {
      try {
        const config = JSON.parse(raw);
        if (config.instructions != null && !Array.isArray(config.instructions)) throw new Error('instructions must be an array');
        for (const pattern of (config.instructions || []).slice(0, 128)) {
          if (typeof pattern !== 'string' || /^(?:https?:|\/|[A-Za-z]:)/.test(pattern)
            || pattern.includes('\\') || pattern.split('/').includes('..')) { unresolved.push('external or unsafe instruction pattern'); continue; }
          if (!/[*?{}\[\]]/.test(pattern)) {
            if (safe(pattern)) add(pattern); else unresolved.push(`${pattern}: missing or unsafe`);
            continue;
          }
          // A single-directory *.md glob is common and has an unambiguous contract.
          const match = pattern.match(/^([^*?{}\[\]]+)\/\*\.(md|mdc)$/);
          if (match) directory(match[1], (_, n) => n.endsWith(`.${match[2]}`));
          else unresolved.push(`${pattern}: complex glob requires native resolution`);
        }
        if ((config.instructions || []).length > 128) unresolved.push('instruction patterns exceed 128-entry inspection limit');
      } catch { unresolved.push('opencode.json: invalid configuration'); }
    }
  } else if (adapter === 'cursor') {
    add('AGENTS.md');
    directory('.cursor/rules', (s, n) => n.endsWith('.mdc') && /^alwaysApply:\s*true\s*$/m.test(s));
    unresolved.push('Cursor client/version and nested-rule activation require native verification');
  } else if (adapter === 'copilot') {
    add('.github/copilot-instructions.md');
    unresolved.push('Copilot client determines whether AGENTS.md and applyTo instructions also load');
  } else if (adapter === 'gemini') {
    add('GEMINI.md');
    unresolved.push('Gemini configured context filenames/imports require native verification');
  }
  const entries = [...files].sort().map(file => ({ path: file, bytes: fs.statSync(path.join(target, file)).size }));
  const bytes = entries.reduce((n, f) => n + f.bytes, 0);
  if (bytes > 16 * 1024) warnings.push('Known active project instructions exceed 16 KiB; inspect duplicate kernels and move task-specific detail to references.');
  if (adapter !== 'codex' && files.has('AGENTS.md') && (managed.length || files.size > 1)) warnings.push('AGENTS.md co-loads with this adapter; inspect repeated CONDUCTOR kernels before claiming savings.');
  const state = path.join(target, 'docs/CURRENT_WORK.md');
  if (safe('docs/CURRENT_WORK.md') && fs.statSync(state).size > 32 * 1024) warnings.push('CURRENT_WORK.md exceeds 32 KiB; keep a compact active summary and archive completed history. Read only relevant ranges.');
  return { scope: 'known project files only; excludes global/parent instructions, catalogs, history, and on-demand reads',
    bytes_lower_bound: bytes, files: entries, unresolved, warnings };
}

module.exports = { inspect };
