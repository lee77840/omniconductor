import { spawn } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';

export interface ShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface ShellRunOptions {
  cwd?: string;
  outputChannel: vscode.OutputChannel;
  cancellationToken?: vscode.CancellationToken;
}

/**
 * Locate a usable bash interpreter.
 *
 * Resolution:
 *   1. `conductor.shellPath` setting if non-empty.
 *   2. Mac/Linux: `bash` (assumed on PATH).
 *   3. Windows: try Git Bash standard install paths, then an explicit
 *      development WSL distro (never docker-desktop), then surface an error.
 *
 * Returns either:
 *   - `{ kind: 'native', cmd, args: [] }` — invoke directly.
 *   - `{ kind: 'wsl', cmd: 'wsl.exe', args: [...] }` — invoke in one named WSL distro.
 *   - `undefined` — bash not found; caller surfaces install instructions.
 */
export type BashLauncher =
  | { kind: 'native' | 'wsl'; cmd: string; prefixArgs: string[] }
  | undefined;

export async function detectBash(): Promise<BashLauncher> {
  const override = vscode.workspace
    .getConfiguration('conductor')
    .get<string>('shellPath', '');
  if (override && (await fileExists(override))) {
    return { kind: 'native', cmd: override, prefixArgs: [] };
  }

  if (os.platform() !== 'win32') {
    // Trust PATH — bash is universal on Mac/Linux.
    return { kind: 'native', cmd: 'bash', prefixArgs: [] };
  }

  // Windows: probe Git Bash first.
  const gitBashCandidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files\\Git\\usr\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
    path.join(os.homedir(), 'AppData', 'Local', 'Programs', 'Git', 'bin', 'bash.exe'),
  ];
  for (const candidate of gitBashCandidates) {
    if (await fileExists(candidate)) {
      return { kind: 'native', cmd: candidate, prefixArgs: [] };
    }
  }

  // WSL is safe only when Node + bash run together inside a named development
  // distro. The Docker Desktop utility distros are not user environments and
  // must never be selected from the machine's default-distro setting.
  const distributions = await listWslDistributions();
  const configuredDistro = vscode.workspace
    .getConfiguration('conductor')
    .get<string>('wslDistribution', '')
    .trim();
  const distro = configuredDistro
    ? distributions.find((item) => item.toLowerCase() === configuredDistro.toLowerCase())
    : distributions[0];
  if (distro) {
    return {
      kind: 'wsl',
      cmd: 'wsl.exe',
      prefixArgs: ['--distribution', distro, '--', 'bash'],
    };
  }

  return undefined;
}

/**
 * Run a transform.sh-style command, streaming stdout/stderr line-by-line into
 * the supplied output channel. Honors VSCode cancellation by killing the child.
 */
export async function runBashScript(
  scriptPath: string,
  scriptArgs: string[],
  launcher: NonNullable<BashLauncher>,
  options: ShellRunOptions,
): Promise<ShellResult> {
  return new Promise((resolve, reject) => {
    const finalScript = launcher.kind === 'wsl' ? toWslPath(scriptPath) : scriptPath;
    const finalArgs = launcher.kind === 'wsl'
      ? scriptArgs.map(toWslPathIfAbsolute)
      : scriptArgs;

    const args = [...launcher.prefixArgs, finalScript, ...finalArgs];

    options.outputChannel.appendLine(
      `[conductor] $ ${launcher.cmd} ${args.map(quoteIfNeeded).join(' ')}`,
    );

    const child = spawn(launcher.cmd, args, {
      cwd: options.cwd,
      env: process.env,
      shell: false,
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk: Buffer) => {
      const text = chunk.toString();
      stdout += text;
      options.outputChannel.append(text);
    });
    child.stderr.on('data', (chunk: Buffer) => {
      const text = chunk.toString();
      stderr += text;
      options.outputChannel.append(text);
    });

    options.cancellationToken?.onCancellationRequested(() => {
      child.kill('SIGTERM');
    });

    child.on('error', reject);
    child.on('close', (exitCode) => {
      resolve({ exitCode: exitCode ?? -1, stdout, stderr });
    });
  });
}

async function fileExists(p: string): Promise<boolean> {
  try {
    await fs.promises.access(p, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function listWslDistributions(): Promise<string[]> {
  return new Promise((resolve) => {
    const child = spawn('wsl.exe', ['--list', '--quiet'], { shell: false, windowsHide: true });
    const chunks: Buffer[] = [];
    let settled = false;
    const finish = (value: string[]) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => {
      child.kill();
      finish([]);
    }, 5000);
    child.stdout.on('data', (chunk: Buffer) => chunks.push(chunk));
    child.on('error', () => finish([]));
    child.on('close', (code) => {
      if (code !== 0) return finish([]);
      const raw = Buffer.concat(chunks);
      const encoding: BufferEncoding = raw.includes(0) ? 'utf16le' : 'utf8';
      const names = raw.toString(encoding).replace(/\0/g, '').split(/\r?\n/)
        .map((item) => item.trim())
        .filter((item) => item.length > 0)
        .filter((item) => !['docker-desktop', 'docker-desktop-data'].includes(item.toLowerCase()));
      finish(names);
    });
  });
}

/**
 * Translate a Windows path (`C:\foo\bar`) into a WSL path (`/mnt/c/foo/bar`).
 * Mirrors Git Bash / MSYS conventions. Used only when launching via WSL.
 */
function toWslPath(p: string): string {
  if (!/^[A-Za-z]:/.test(p)) {
    return p; // already POSIX-shaped
  }
  const drive = p[0].toLowerCase();
  const rest = p.slice(2).replace(/\\/g, '/');
  return `/mnt/${drive}${rest}`;
}

function toWslPathIfAbsolute(arg: string): string {
  if (/^[A-Za-z]:/.test(arg)) {
    return toWslPath(arg);
  }
  return arg;
}

function quoteIfNeeded(s: string): string {
  return /[\s"]/.test(s) ? `"${s.replace(/"/g, '\\"')}"` : s;
}
