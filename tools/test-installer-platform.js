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

// Closes the class, not one instance. Windows resolves a bare `bash` to the WSL
// relay (System32\bash.exe), which spawns successfully and exits non-zero when
// no distribution provides /bin/bash. Product code that spawned it that way
// reported every emitted hook as a syntax error on a correct install, and the
// suite itself could not run on Windows at all. Any new call site must resolve
// the interpreter through installer-platform instead.
const ROOT = path.join(__dirname, '..');
const offenders = [];
for (const dir of ['bin', 'tools']) {
  const base = path.join(ROOT, dir);
  for (const name of fs.readdirSync(base)) {
    if (!name.endsWith('.js')) continue;
    const file = path.join(base, name);
    const source = fs.readFileSync(file, 'utf8');
    for (const [index, line] of source.split('\n').entries()) {
      if (/^\s*(\/\/|\*)/.test(line)) continue;
      // Every shape that ends up as argv[0]: a direct spawn, a helper called as
      // run('bash', …), and an argv array whose first element is the literal.
      if (/(?:spawnSync|spawn|execFileSync|execFile|execSync|run)\(\s*['"`](?:bash|sh|\/bin\/bash|\/bin\/sh)['"`]\s*[,)]/.test(line)
        || /\[\s*['"`](?:bash|\/bin\/bash)['"`]\s*,/.test(line)
        // A multi-line argv array puts the interpreter alone on its own line.
        || /^\s*['"`](?:bash|\/bin\/bash)['"`]\s*,\s*$/.test(line)) {
        offenders.push(`${dir}/${name}:${index + 1}`);
      }
    }
  }
}
assert.deepStrictEqual(
  offenders,
  [],
  `these call sites spawn a bare 'bash' and break on Windows; resolve it through bin/installer-platform.js resolveBash(): ${offenders.join(', ')}`,
);

// npm uses cmd.exe for scripts on Windows. Package scripts therefore cannot
// contain POSIX control flow or launch a bare bash; both bypass the resolved
// interpreter contract even when the product CLI itself is correct.
const packageScripts = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')).scripts;
const unsafePackageScripts = [];
for (const [name, command] of Object.entries(packageScripts)) {
  if (/(^|[;&|]\s*)bash\s+/.test(command) || /\bfor\s+\w+\s+in\s+.*;\s*do\b/.test(command)) {
    unsafePackageScripts.push(name);
  }
}
assert.deepStrictEqual(
  unsafePackageScripts,
  [],
  `package scripts bypass the cross-platform Bash runner: ${unsafePackageScripts.join(', ')}`,
);
assert(fs.existsSync(path.join(ROOT, 'tools', 'run-bash.js')));
assert(fs.existsSync(path.join(ROOT, 'tools', 'test-install-modes-all.js')));
const windowsInstallerSource = fs.readFileSync(path.join(ROOT, 'tools', 'test-windows-installer.js'), 'utf8');
assert.match(windowsInstallerSource, /ALL_TARGET_TIMEOUT_MS\s*=\s*600_000/);
assert.match(windowsInstallerSource, /DIRECT_TIMEOUT_MS\s*=\s*180_000/);
assert.match(windowsInstallerSource, /elapsedMs=.*timeoutMs=.*error=/);
assert.match(windowsInstallerSource, /runDirectAdapter\(tool, target\)/);
assert.match(windowsInstallerSource, /'--mode=minimal', '--recipes='/);
assert.match(windowsInstallerSource,
  /'init', '--target=all', lifecycle, '--mode=minimal', '--recipes='/);
assert.match(windowsInstallerSource, /\[windows-installer\]/);

// Same class again: the Claude adapter's completion summary hardcoded "Roles: 7"
// while it emitted 8, so the installer under-reported its own output on every
// full install. Counts printed to adopters must be derived from the shipped
// sources, never written as a literal that can drift away from them.
const literalCounts = [];
const adapterRoot = path.join(ROOT, 'adapters');
for (const tool of fs.readdirSync(adapterRoot)) {
  const script = path.join(adapterRoot, tool, 'transform.sh');
  if (!fs.existsSync(script)) continue;
  for (const [index, line] of fs.readFileSync(script, 'utf8').split('\n').entries()) {
    if (/^\s*#/.test(line)) continue;
    // 0 and 1 are mode-determined constants (à la carte emits none, or the
    // single reflector). Any inventory count of two or more must be derived.
    if (/(Roles|Universal rules):\s*(?:[2-9]|\d\d)/.test(line) && !/\$\(/.test(line)) {
      literalCounts.push(`adapters/${tool}/transform.sh:${index + 1}`);
    }
  }
}
assert.deepStrictEqual(
  literalCounts,
  [],
  `these summary lines hardcode a count that can drift from core/: ${literalCounts.join(', ')}`,
);

console.log('PASS: Windows Git Bash discovery is explicit and overrideable');
console.log('PASS: no call site spawns a bare bash that Windows maps to the WSL relay');
console.log('PASS: adapter summaries derive role and rule counts from core sources');
console.log('PASS: WSL output decoding excludes infrastructure-only distributions');
console.log('PASS: installer environment reports supported Node/shell pairings truthfully');
console.log('PASS: Windows Git Bash script usability does not invent POSIX mode-bit failures');
console.log('PASS: npm scripts use the resolved Bash runner instead of cmd-incompatible POSIX syntax');
console.log('PASS: Windows all-target lifecycle has a bounded slow-host budget and actionable timeout diagnostics');

// Relative paths that reach a manifest, journal, or ownership ledger must be
// POSIX. path.join() yields backslashes on Windows, and path-safety rejects
// those as non-portable, so a crash journal written on Windows could not be
// replayed by its own recovery path.
const nativeRelConstants = [];
for (const dir of ['bin', 'tools']) {
  const base = path.join(ROOT, dir);
  for (const name of fs.readdirSync(base)) {
    if (!name.endsWith('.js')) continue;
    fs.readFileSync(path.join(base, name), 'utf8').split('\n').forEach((line, index) => {
      if (/^\s*#/.test(line)) return;
      if (/^\s*const\s+\w*(REL|Rel)\w*\s*=\s*path\.join\(/.test(line)) {
        nativeRelConstants.push(`${dir}/${name}:${index + 1}`);
      }
    });
  }
}
assert.deepStrictEqual(
  nativeRelConstants,
  [],
  `these relative-path constants use path.join and become backslashed on Windows: ${nativeRelConstants.join(', ')}`,
);
console.log('PASS: manifest-relative constants stay POSIX on every platform');

// A relative path that is stored — pushed into a list, assigned, compared —
// must be POSIX, because it gets matched against manifest entries, git
// pathspecs, and expected-path fixtures that are all forward-slashed. Message
// interpolation inside a template literal is exempt: a backslash there is only
// cosmetic on Windows.
const unnormalizedRelatives = [];
for (const dir of ['bin', 'tools']) {
  const base = path.join(ROOT, dir);
  for (const name of fs.readdirSync(base)) {
    if (!name.endsWith('.js')) continue;
    fs.readFileSync(path.join(base, name), 'utf8').split('\n').forEach((line, index) => {
      if (/^\s*(\/\/|\*)/.test(line)) return;
      if (!/path\.relative\(/.test(line)) return;
      // Both normalization idioms in use here count as normalized.
      // An explicit `native-path-compare` marker exempts a relative path that is
      // consumed as a platform-native value — containment tests that use
      // path.sep and path.isAbsolute — where forcing POSIX would break the
      // comparison. The marker keeps the exception visible in review.
      if (/\.replace\(|\.split\(path\.sep\)|native-path-compare/.test(line) || line.includes('`')) return;
      unnormalizedRelatives.push(`${dir}/${name}:${index + 1}`);
    });
  }
}
assert.deepStrictEqual(
  unnormalizedRelatives,
  [],
  `these stored relative paths keep Windows backslashes: ${unnormalizedRelatives.join(', ')}`,
);
console.log('PASS: stored relative paths are normalized to POSIX');
