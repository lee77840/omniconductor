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
  // `gamma` is the fixture's single stack-specific recipe, so the documented
  // stack-agnostic total must derive to 2 rather than a hardcoded count - 1.
  write(path.join(root, 'core', 'recipes', 'gamma.md'), '---\nstack_specific: true\n---\n\n# gamma\n');
  for (const name of ['operations', 'quality-gates']) {
    write(path.join(root, 'core', 'universal-rules', `${name}.md`), `# ${name}\n`);
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

**3 policy-classified recipes**

## Recipes catalog

| Recipe | When |
|---|---|
| \`alpha\` | A |
| \`beta\` | B |
| \`gamma\` | C |

#### Decision tree

3 recipes layer project-specific discipline.

**Recipe names** (3): \`alpha\`, \`beta\`, \`gamma\`.

Check recipe name spelling. Available: \`alpha\`, \`beta\`, \`gamma\`.

3개 recipe options are documented here.

A: Skip \`gamma\` (stack-specific). The 2 universal rule bundles and the other 2 recipes are stack-agnostic.
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

// A guarded sentence that is reworded must fail loudly. Before the presence
// assertion this silently dropped the guard and the gate still reported OK.
root = fixture();
readmePath = path.join(root, 'README.md');
write(readmePath, fs.readFileSync(readmePath, 'utf8').replace('**3 policy-classified recipes**', '**three policy-classified recipes**'));
assert.match(errorsFor(root), /classified recipe count guard matched no living document/);
fs.rmSync(root, { recursive: true, force: true });

// A second stack-specific recipe must move the derived stack-agnostic total
// rather than force the docs to state count - 1.
root = fixture();
write(path.join(root, 'core', 'recipes', 'delta.md'), '---\nstack_specific: true\n---\n\n# delta\n');
readmePath = path.join(root, 'README.md');
write(readmePath, fs.readFileSync(readmePath, 'utf8')
  .replace(/\b3 policy-classified recipes\b/, '4 policy-classified recipes')
  .replace('3 recipes layer project-specific discipline.', '4 recipes layer project-specific discipline.')
  .replace('**Recipe names** (3): `alpha`, `beta`, `gamma`.', '**Recipe names** (4): `alpha`, `beta`, `delta`, `gamma`.')
  .replace('Check recipe name spelling. Available: `alpha`, `beta`, `gamma`.', 'Check recipe name spelling. Available: `alpha`, `beta`, `delta`, `gamma`.')
  .replace('3개 recipe options', '4개 recipe options')
  .replace('| `gamma` | C |', '| `delta` | D |\n| `gamma` | C |'));
const corePath = path.join(root, 'core', 'recipes', 'README.md');
write(corePath, fs.readFileSync(corePath, 'utf8')
  .replace('## The 3 recipes', '## The 4 recipes')
  .replace('| `gamma.md` | C |', '| `delta.md` | D |\n| `gamma.md` | C |'));
// With two stack-specific recipes out of four, "the other 2 are stack-agnostic"
// is the true sentence and must pass. The previous count - 1 rule expected 3
// here, so it would have rejected the correct documentation.
assert.doesNotMatch(errorsFor(root), /stack-agnostic recipe count/);
fs.rmSync(root, { recursive: true, force: true });

console.log('recipe documentation drift tests: 7/7 passed');
