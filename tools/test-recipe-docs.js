#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { validateRecipeDocs } = require('./check-recipe-docs');

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-recipe-docs-'));
  for (const name of ['alpha', 'beta', 'gamma']) {
    write(path.join(root, 'core', 'recipes', `${name}.md`), `# ${name}\n`);
  }
  write(path.join(root, 'core', 'recipes', 'README.md'), `# Recipes

## The 3 recipes

| File | When |
|---|---|
| \`alpha.md\` | A |
| \`beta.md\` | B |
| \`gamma.md\` | C |
`);
  write(path.join(root, 'README.md'), `# Example

**3 opt-in recipes**

## Recipes catalog

| Recipe | When |
|---|---|
| \`alpha\` | A |
| \`beta\` | B |
| \`gamma\` | C |

#### Decision tree

Recipes from the 3 in core.

**Recipe names** (3): \`alpha\`, \`beta\`, \`gamma\`.

Check recipe name spelling. Available: \`alpha\`, \`beta\`, \`gamma\`.

The other 2 recipes are generic.
`);
  return root;
}

function errorsFor(root) {
  return validateRecipeDocs(root).errors.join('\n');
}

let root = fixture();
assert.strictEqual(errorsFor(root), '');
fs.rmSync(root, { recursive: true, force: true });

root = fixture();
write(path.join(root, 'core', 'recipes', 'delta.md'), '# delta\n');
assert.match(errorsFor(root), /expected 4|missing: delta/);
fs.rmSync(root, { recursive: true, force: true });

root = fixture();
let readmePath = path.join(root, 'README.md');
write(readmePath, fs.readFileSync(readmePath, 'utf8').replace('`alpha`, `beta`, `gamma`.', '`alpha`, `beta`.'));
assert.match(errorsFor(root), /recipe names reference recipe catalog drift.*missing: gamma/);
fs.rmSync(root, { recursive: true, force: true });

root = fixture();
readmePath = path.join(root, 'README.md');
write(readmePath, fs.readFileSync(readmePath, 'utf8').replace(
  'Check recipe name spelling. Available: `alpha`, `beta`, `gamma`.',
  'Check recipe name spelling. Available: `alpha`, `beta`, `gamma`, `ghost`.',
));
assert.match(errorsFor(root), /troubleshooting list recipe catalog drift.*extra: ghost/);
fs.rmSync(root, { recursive: true, force: true });

root = fixture();
readmePath = path.join(root, 'README.md');
write(readmePath, fs.readFileSync(readmePath, 'utf8').replace(
  '| `gamma` | C |',
  '| `gamma` | C |\n| `gamma` | duplicate |',
));
assert.match(errorsFor(root), /main table recipe catalog drift.*duplicate: gamma/);
fs.rmSync(root, { recursive: true, force: true });

console.log('recipe documentation drift tests: 5/5 passed');
