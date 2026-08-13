#!/usr/bin/env node
'use strict';

const { runBash } = require('./run-bash.js');

for (const tool of ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode']) {
  const result = runBash('tools/test-install-modes.sh', [tool]);
  if (result.error || result.status !== 0) {
    process.exitCode = Number.isInteger(result.status) ? result.status : 2;
    break;
  }
}
