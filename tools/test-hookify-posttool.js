'use strict';

const assert = require('assert');
const h = require('../bin/claude-hookify.js');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hookify-post-'));
const sp = path.join(dir, 'settings.json');
fs.writeFileSync(sp, JSON.stringify({ enabledPlugins: {} }));

h.ensureConfigured(sp); // installs core hooks
const s = JSON.parse(fs.readFileSync(sp, 'utf8'));
const post = (s.hooks && s.hooks.PostToolUse) || [];
const cmds = post.flatMap((g) => (g.hooks || []).map((x) => x.command));
assert(cmds.some((c) => /output-cap\.sh/.test(c)), 'PostToolUse output-cap not registered');
assert(h.missingCoreHooks(sp).length === 0, 'missingCoreHooks should be empty after configure');

console.log('PASS: hookify PostToolUse');
