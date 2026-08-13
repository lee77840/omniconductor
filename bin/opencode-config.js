#!/usr/bin/env node
'use strict';

// Conservative project-config composer for the OpenCode v1 adapter.
// OpenCode merges project configuration with global configuration, but the two
// project filenames (opencode.json and opencode.jsonc) compete for the same
// scope. CONDUCTOR therefore edits only regular JSON and refuses an ambiguous
// JSONC project instead of guessing precedence or rewriting comments.

const fs = require('fs');
const path = require('path');

const OWNED = [
  '.opencode/rules/*.md',
  '.opencode/rules/recipes/*.md',
];

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function safeRegularFile(file) {
  if (!fs.existsSync(file)) return;
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) {
    throw new Error(`${path.basename(file)} must be a non-linked regular file`);
  }
}

function load(target) {
  const json = path.join(target, 'opencode.json');
  const jsonc = path.join(target, 'opencode.jsonc');
  safeRegularFile(json);
  safeRegularFile(jsonc);
  if (fs.existsSync(jsonc)) {
    throw new Error('opencode.jsonc already exists; CONDUCTOR will not create a competing opencode.json or rewrite commented JSON');
  }
  if (!fs.existsSync(json)) return { file: json, config: {} };
  let config;
  try { config = JSON.parse(fs.readFileSync(json, 'utf8')); }
  catch (error) { throw new Error(`opencode.json is invalid JSON: ${error.message}`); }
  if (!isPlainObject(config)) throw new Error('opencode.json must contain a JSON object');
  if (config.instructions !== undefined && !Array.isArray(config.instructions)) {
    throw new Error('opencode.json instructions must be an array');
  }
  return { file: json, config };
}

function compose(target, selected) {
  const { file, config } = load(target);
  const prior = Array.isArray(config.instructions) ? config.instructions : [];
  const instructions = prior.filter((item) => !OWNED.includes(item));
  for (const item of selected) if (!instructions.includes(item)) instructions.push(item);
  const next = { $schema: 'https://opencode.ai/config.json', ...config, instructions };
  if (config.$schema !== undefined) next.$schema = config.$schema;
  return { file, config: next };
}

function main(argv) {
  const [command, target, mode] = argv;
  if (!['compose', 'validate'].includes(command) || !target) {
    throw new Error('Usage: opencode-config.js compose|validate <target> [baseline|recipes|all]');
  }
  const absolute = path.resolve(target);
  if (command === 'validate') {
    load(absolute);
    return;
  }
  const selected = mode === 'baseline' ? [OWNED[0]]
    : mode === 'recipes' ? [OWNED[1]]
      : mode === 'all' ? OWNED : [];
  const result = compose(absolute, selected);
  fs.writeFileSync(result.file, `${JSON.stringify(result.config, null, 2)}\n`, { mode: 0o644 });
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    process.stderr.write(`OpenCode config: ${error.message}\n`);
    process.exitCode = 2;
  }
}

module.exports = { OWNED, compose, load };
