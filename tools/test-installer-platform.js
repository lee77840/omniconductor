#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const platform = require('../bin/installer-platform.js');

const env = {
  CONDUCTOR_BASH_PATH: 'C:\\portable\\git\\bash.exe',
  ProgramFiles: 'C:\\Program Files',
  'ProgramFiles(x86)': 'C:\\Program Files (x86)',
  LOCALAPPDATA: 'C:\\Users\\test\\AppData\\Local',
};
const candidates = platform.gitBashCandidates(env, 'C:\\Users\\test');
assert.strictEqual(candidates[0], env.CONDUCTOR_BASH_PATH);
assert(candidates.includes(path.join(env.ProgramFiles, 'Git', 'bin', 'bash.exe')));
assert(candidates.includes(path.join(env.LOCALAPPDATA, 'Programs', 'Git', 'bin', 'bash.exe')));

const resolved = platform.resolveBash({
  platform: 'win32', env, home: 'C:\\Users\\test', exists: (candidate) => candidate === env.CONDUCTOR_BASH_PATH,
});
assert.deepStrictEqual(resolved, { kind: 'git-bash', command: env.CONDUCTOR_BASH_PATH, source: env.CONDUCTOR_BASH_PATH });
assert.strictEqual(platform.resolveBash({ platform: 'win32', env: {}, home: 'C:\\empty', exists: () => false }), null);
assert.deepStrictEqual(platform.resolveBash({ platform: 'linux' }), { kind: 'native', command: 'bash', source: 'PATH' });

const utf16 = Buffer.from('Ubuntu-24.04\r\ndocker-desktop\r\nDebian\r\n', 'utf16le');
const utf8 = Buffer.from('Ubuntu\nDebian\n', 'utf8');
assert.match(platform.decodeWslOutput(utf16), /Ubuntu-24\.04/);
assert.strictEqual(platform.decodeWslOutput(utf8), 'Ubuntu\nDebian\n');
assert.deepStrictEqual(
  platform.developmentWslDistributions(['docker-desktop', 'Ubuntu-24.04', 'DOCKER-DESKTOP-DATA', 'Debian']),
  ['Ubuntu-24.04', 'Debian'],
);
assert.deepStrictEqual(platform.listWslDistributions({
  spawn: () => ({ status: 0, stdout: utf16 }),
}), ['Ubuntu-24.04', 'docker-desktop', 'Debian']);
assert.deepStrictEqual(platform.listWslDistributions({
  spawn: () => ({ status: 1, stdout: Buffer.alloc(0) }),
}), []);

let report = platform.installerEnvironment({
  platform: 'win32', env, home: 'C:\\Users\\test', exists: (candidate) => candidate === env.CONDUCTOR_BASH_PATH,
  spawn: () => ({ status: 0, stdout: utf16 }),
});
assert.strictEqual(report.mode, 'windows-git-bash');
assert.strictEqual(report.supported, true);
assert.deepStrictEqual(report.wsl_distributions, []);

report = platform.installerEnvironment({ platform: 'linux', env: { WSL_DISTRO_NAME: 'docker-desktop' } });
assert.strictEqual(report.mode, 'wsl-linux');
assert.strictEqual(report.supported, false);

const scriptDir = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-script-mode-'));
const script = path.join(scriptDir, 'hook.sh');
fs.writeFileSync(script, '#!/usr/bin/env bash\nexit 0\n', { mode: 0o600 });
assert.strictEqual(platform.shellScriptUsable(script, { platform: 'win32' }), true);
assert.strictEqual(platform.shellScriptUsable(script, {
  platform: 'linux', access: () => { throw new Error('not executable'); },
}), false);
assert.strictEqual(platform.shellScriptUsable(script, { platform: 'linux', access: () => {} }), true);
fs.rmSync(scriptDir, { recursive: true, force: true });

console.log('PASS: Windows Git Bash discovery is explicit and overrideable');
console.log('PASS: WSL output decoding excludes infrastructure-only distributions');
console.log('PASS: installer environment reports supported Node/shell pairings truthfully');
console.log('PASS: Windows Git Bash script usability does not invent POSIX mode-bit failures');
