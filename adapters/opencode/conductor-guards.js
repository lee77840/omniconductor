// CONDUCTOR native OpenCode v1 guards.
// Project-local plugins are auto-loaded by OpenCode. This plugin inspects only
// Bash tool calls that contain `git commit`; it never executes the requested
// command and never logs prompt, response, environment, or tool payload data.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

function git(root, args) {
  return execFileSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
    timeout: 5000,
  }).trim()
}

function isCommit(command) {
  return /(^|[;&|()\s])git\s+(?:(?:(?:-C|-c|--git-dir|--work-tree)\s+\S+|--(?:git-dir|work-tree)=\S+|-[A-Za-z]+)\s+)*commit(?:\s|$)/.test(command)
}

function staged(root) {
  try { return git(root, ['diff', '--cached', '--name-only', '--diff-filter=ACMR']).split(/\r?\n/).filter(Boolean) }
  catch { return [] }
}

function hasSource(files) {
  return files.some((file) => /(?:^|\/)(?:src|app|apps|lib|packages)\//.test(file)
    && !/(?:^|\/)(?:test|tests|__tests__|fixtures)\//.test(file)
    && !/\.(?:test|spec)\.[^.]+$/.test(file))
}

function hasTest(files) {
  return files.some((file) => /(?:^|\/)(?:test|tests|__tests__|e2e|fixtures)\//.test(file)
    || /\.(?:test|spec)\.[^.]+$/.test(file))
}

export const ConductorGuards = async ({ worktree, directory }) => {
  const root = worktree || directory || process.cwd()
  return {
    'tool.execute.before': async (input, output) => {
      if (input.tool !== 'bash') return
      const command = String(output?.args?.command || '')
      if (!isCommit(command)) return
      const files = staged(root)
      if (!files.length) return

      const currentWork = join(root, 'docs', 'CURRENT_WORK.md')
      if (existsSync(currentWork) && !files.includes('docs/CURRENT_WORK.md')) {
        const body = readFileSync(currentWork, 'utf8')
        if (/\b(?:IN_PROGRESS|in progress|active)\b/i.test(body)) {
          throw new Error('CONDUCTOR guard: docs/CURRENT_WORK.md records active work but is not staged. Update/stage it or explicitly resolve the active state before committing.')
        }
      }

      if (hasSource(files) && !hasTest(files)) {
        throw new Error('CONDUCTOR guard: staged source changes have no staged test evidence. Add/update tests, or record the justified verification exception before committing.')
      }
    },
  }
}
