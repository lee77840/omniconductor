#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
const installerPlatform = require('../bin/installer-platform.js');

function bashPath(value) {
  return process.platform === 'win32' ? value.replace(/\\/g, '/') : value;
}

function runBash(script, args = [], options = {}) {
  const bash = options.bash || installerPlatform.resolveBash(options.platformOptions);
  if (!bash) {
    return {
      status: 2,
      error: new Error('Git Bash was not found. Install Git for Windows or set CONDUCTOR_BASH_PATH to bash.exe.'),
    };
  }
  const root = options.cwd || path.resolve(__dirname, '..');
  const absoluteScript = path.isAbsolute(script) ? script : path.resolve(root, script);
  return spawnSync(bash.command, [bashPath(absoluteScript), ...args], {
    cwd: root,
    stdio: options.stdio || 'inherit',
    encoding: options.encoding,
    input: options.input,
    timeout: options.timeout,
    windowsHide: true,
    env: { ...process.env, CONDUCTOR_BASH_PATH: bash.command, ...(options.env || {}) },
  });
}

function main(argv) {
  const [script, ...args] = argv;
  if (!script) {
    process.stderr.write('usage: node tools/run-bash.js <script> [args...]\n');
    return 2;
  }
  const result = runBash(script, args);
  if (result.error) process.stderr.write(`conductor bash runner: ${result.error.message}\n`);
  if (Number.isInteger(result.status)) return result.status;
  return 2;
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));

module.exports = { bashPath, runBash };
