'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const INTERNAL_WSL = new Set(['docker-desktop', 'docker-desktop-data']);

function gitBashCandidates(env = process.env, home = os.homedir()) {
  const candidates = [];
  if (env.CONDUCTOR_BASH_PATH) candidates.push(env.CONDUCTOR_BASH_PATH);
  for (const base of [env.ProgramFiles, env['ProgramFiles(x86)']]) {
    if (!base) continue;
    candidates.push(path.join(base, 'Git', 'bin', 'bash.exe'));
    candidates.push(path.join(base, 'Git', 'usr', 'bin', 'bash.exe'));
  }
  if (env.LOCALAPPDATA) candidates.push(path.join(env.LOCALAPPDATA, 'Programs', 'Git', 'bin', 'bash.exe'));
  candidates.push(path.join(home, 'AppData', 'Local', 'Programs', 'Git', 'bin', 'bash.exe'));
  return [...new Set(candidates)];
}

function resolveBash(options = {}) {
  const platform = options.platform || process.platform;
  const exists = options.exists || fs.existsSync;
  const env = options.env || process.env;
  if (platform !== 'win32') return { kind: 'native', command: 'bash', source: 'PATH' };
  for (const candidate of gitBashCandidates(env, options.home || os.homedir())) {
    if (path.win32.isAbsolute(candidate) && exists(candidate)) {
      return { kind: 'git-bash', command: candidate, source: candidate };
    }
  }
  return null;
}

function decodeWslOutput(buffer) {
  if (!Buffer.isBuffer(buffer)) return String(buffer || '').replace(/\0/g, '');
  const encoding = buffer.includes(0) ? 'utf16le' : 'utf8';
  return buffer.toString(encoding).replace(/\0/g, '');
}

function listWslDistributions(options = {}) {
  const spawn = options.spawn || spawnSync;
  const result = spawn('wsl.exe', ['--list', '--quiet'], { encoding: 'buffer', windowsHide: true, timeout: 5000 });
  if (result.error || result.status !== 0) return [];
  return decodeWslOutput(result.stdout).split(/\r?\n/).map((item) => item.trim()).filter(Boolean);
}

function developmentWslDistributions(distributions) {
  return distributions.filter((item) => !INTERNAL_WSL.has(item.toLowerCase()));
}

function installerEnvironment(options = {}) {
  const platform = options.platform || process.platform;
  const env = options.env || process.env;
  if (platform !== 'win32') {
    const distro = env.WSL_DISTRO_NAME || null;
    return {
      platform,
      mode: distro ? 'wsl-linux' : 'native-posix',
      distro,
      supported: !distro || !INTERNAL_WSL.has(distro.toLowerCase()),
      bash: { kind: 'native', command: 'bash', source: 'PATH' },
      wsl_distributions: [],
    };
  }
  const bash = resolveBash(options);
  const wsl = bash ? [] : developmentWslDistributions(listWslDistributions(options));
  return {
    platform,
    mode: bash ? 'windows-git-bash' : 'windows-no-git-bash',
    distro: null,
    supported: !!bash,
    bash,
    wsl_distributions: wsl,
  };
}

function shellScriptUsable(file, options = {}) {
  const platform = options.platform || process.platform;
  const access = options.access || fs.accessSync;
  try {
    const stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink()) return false;
    if (platform === 'win32') return true;
    access(file, fs.constants.X_OK);
    return true;
  } catch { return false; }
}

module.exports = {
  INTERNAL_WSL, decodeWslOutput, developmentWslDistributions, gitBashCandidates,
  installerEnvironment, listWslDistributions, resolveBash, shellScriptUsable,
};
