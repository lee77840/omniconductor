#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const coverage = require('../bin/assurance-coverage.js');

const ROOT = path.resolve(__dirname, '..');
const outputs = {
  'docs/AGENT-EVAL-COVERAGE.json': `${JSON.stringify(coverage.buildReport(), null, 2)}\n`,
};
outputs['docs/AGENT-EVAL-COVERAGE.md'] = coverage.render(JSON.parse(outputs['docs/AGENT-EVAL-COVERAGE.json']));

let stale = false;
for (const [relative, expected] of Object.entries(outputs)) {
  const file = path.join(ROOT, relative);
  if (process.argv.includes('--check')) {
    const actual = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
    if (actual !== expected) {
      process.stderr.write(`assurance coverage is stale: ${relative}\n`);
      stale = true;
    }
  } else {
    fs.writeFileSync(file, expected);
    process.stdout.write(`wrote ${relative}\n`);
  }
}
if (stale) process.exit(1);
