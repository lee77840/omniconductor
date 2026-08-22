'use strict';

const fs = require('fs');
const path = require('path');

const HOOKIFY_PLUGIN_ID = 'hookify@claude-plugins-official';
const BASE_CORE_HOOK_GROUPS = [
  { event: 'PreToolUse', matcher: 'Agent', commands: ['.claude/hooks/pretool-agent-routing.sh'] },
  { event: 'PreToolUse', matcher: 'Bash', commands: [
    '.claude/hooks/pretool-commit-current-work-check.sh',
    '.claude/hooks/pretool-commit-test-coverage-check.sh',
  ] },
  { event: 'PreToolUse', matcher: 'Read', commands: ['.claude/hooks/pretool-large-file-read-guard.sh'] },
  { event: 'PreToolUse', matcher: '*', commands: ['.claude/hooks/pretool-loop-guard.sh'] },
  { event: 'PostToolUse', matcher: '*', commands: ['.claude/hooks/output-cap.sh'] },
  { event: 'Stop', commands: [
    '.claude/hooks/stop-session-log-check.sh',
    '.claude/hooks/stop-r6-review-check.sh',
    '.claude/hooks/stop-cache-hit-baseline-check.sh',
    '.claude/hooks/stop-git-hygiene-guard.sh',
  ] },
];
const TRAJECTORY_COMMAND = '.claude/hooks/stop-trajectory-log.sh';

function coreHookGroups(options = {}) {
  const groups = BASE_CORE_HOOK_GROUPS.map((group) => ({
    ...group, commands: [...group.commands],
  }));
  if (options.selfImprovement) {
    groups.find((group) => group.event === 'Stop').commands.push(TRAJECTORY_COMMAND);
  }
  return groups;
}

function readSettings(settingsPath) {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
  } catch (error) {
    throw new Error(`${settingsPath} is not valid JSON: ${error.message}`);
  }
  if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
    throw new Error(`${settingsPath} must contain a JSON object`);
  }
  if (parsed.enabledPlugins !== undefined
      && (!parsed.enabledPlugins || Array.isArray(parsed.enabledPlugins)
        || typeof parsed.enabledPlugins !== 'object')) {
    throw new Error(`${settingsPath} enabledPlugins must be a JSON object`);
  }
  if (parsed.hooks !== undefined
      && (!parsed.hooks || Array.isArray(parsed.hooks) || typeof parsed.hooks !== 'object')) {
    throw new Error(`${settingsPath} hooks must be a JSON object`);
  }
  for (const event of ['PreToolUse', 'PostToolUse', 'Stop']) {
    if (parsed.hooks && parsed.hooks[event] !== undefined && !Array.isArray(parsed.hooks[event])) {
      throw new Error(`${settingsPath} hooks.${event} must be a JSON array`);
    }
  }
  return parsed;
}

function normalizedCommand(command) {
  return String(command || '').replace(/^"?\$CLAUDE_PROJECT_DIR"?\//, '');
}

function registeredCoreHooks(settings) {
  const registered = new Set();
  for (const event of ['PreToolUse', 'PostToolUse', 'Stop']) {
    for (const group of (settings.hooks && settings.hooks[event]) || []) {
      const matcher = String((group && group.matcher) || '');
      for (const hook of (group && Array.isArray(group.hooks) ? group.hooks : [])) {
        const command = normalizedCommand(hook && hook.command);
        if (command) registered.add(`${event}\0${matcher}\0${command}`);
      }
    }
  }
  return registered;
}

function missingCoreHooks(settingsPath, options = {}) {
  const settings = typeof settingsPath === 'string' ? readSettings(settingsPath) : settingsPath;
  const registered = registeredCoreHooks(settings);
  return coreHookGroups(options).flatMap((group) => group.commands.map((command) => ({ group, command })))
    .filter(({ group, command }) => !registered.has(`${group.event}\0${group.matcher || ''}\0${command}`))
    .map(({ command }) => command);
}

function configuredState(settingsPath) {
  if (!fs.existsSync(settingsPath)) return 'absent';
  const settings = readSettings(settingsPath);
  if (!settings.enabledPlugins
      || !Object.prototype.hasOwnProperty.call(settings.enabledPlugins, HOOKIFY_PLUGIN_ID)) {
    return 'missing';
  }
  return settings.enabledPlugins[HOOKIFY_PLUGIN_ID] === true ? 'enabled' : 'disabled';
}

function removeExactCommand(settings, command) {
  let changed = false;
  for (const event of ['PreToolUse', 'PostToolUse', 'Stop']) {
    const groups = (settings.hooks && settings.hooks[event]) || [];
    const keptGroups = [];
    let eventChanged = false;
    for (const group of groups) {
      if (!group || !Array.isArray(group.hooks)) { keptGroups.push(group); continue; }
      const hooks = group.hooks.filter((hook) => normalizedCommand(hook && hook.command) !== command);
      if (hooks.length !== group.hooks.length) {
        changed = true;
        eventChanged = true;
      }
      if (hooks.length) keptGroups.push({ ...group, hooks });
      else if (group.hooks.length === 0) keptGroups.push(group);
    }
    if (settings.hooks && eventChanged) settings.hooks[event] = keptGroups;
  }
  return changed;
}

function needsReconcile(settingsPath, options = {}) {
  const settings = readSettings(settingsPath);
  if (missingCoreHooks(settings, options).length) return true;
  return Boolean(options.removeTrajectory && registeredCoreHooks(settings)
    .has(`Stop\0\0${TRAJECTORY_COMMAND}`));
}

function ensureConfigured(settingsPath, options = {}) {
  const settings = readSettings(settingsPath);
  settings.enabledPlugins = settings.enabledPlugins || {};
  let changed = false;
  if (!Object.prototype.hasOwnProperty.call(settings.enabledPlugins, HOOKIFY_PLUGIN_ID)) {
    settings.enabledPlugins[HOOKIFY_PLUGIN_ID] = true;
    changed = true;
  }

  settings.hooks = settings.hooks || {};
  if (options.removeTrajectory && removeExactCommand(settings, TRAJECTORY_COMMAND)) changed = true;
  const registered = registeredCoreHooks(settings);
  for (const group of coreHookGroups(options)) {
    const key = (command) => `${group.event}\0${group.matcher || ''}\0${command}`;
    const missing = group.commands.filter((command) => !registered.has(key(command)));
    if (!missing.length) continue;
    settings.hooks[group.event] = settings.hooks[group.event] || [];
    settings.hooks[group.event].push({
      ...(group.matcher ? { matcher: group.matcher } : {}),
      hooks: missing.map((command) => ({
        type: 'command', command: `"$CLAUDE_PROJECT_DIR"/${command}`,
      })),
    });
    for (const command of missing) registered.add(key(command));
    changed = true;
  }

  if (!changed) return { changed: false, state: configuredState(settingsPath) };
  const mode = fs.statSync(settingsPath).mode & 0o777;
  const tempPath = `${settingsPath}.conductor-hookify-${process.pid}.tmp`;
  try {
    fs.writeFileSync(tempPath, `${JSON.stringify(settings, null, 2)}\n`, { mode, flag: 'wx' });
    fs.renameSync(tempPath, settingsPath);
  } finally {
    try { fs.unlinkSync(tempPath); } catch { /* rename already consumed it */ }
  }
  return { changed: true, state: configuredState(settingsPath) };
}

function localOverrideState(targetAbs) {
  const localPath = path.join(targetAbs, '.claude', 'settings.local.json');
  if (!fs.existsSync(localPath)) return 'absent';
  return configuredState(localPath);
}

if (require.main === module) {
  const [command, settingsPath, ...flags] = process.argv.slice(2);
  const options = {
    selfImprovement: flags.includes('--self-improvement'),
    removeTrajectory: flags.includes('--remove-trajectory'),
  };
  try {
    if (command === 'state' && settingsPath) {
      process.stdout.write(`${configuredState(path.resolve(settingsPath))}\n`);
    } else if (command === 'missing-hooks' && settingsPath) {
      process.stdout.write(`${missingCoreHooks(path.resolve(settingsPath), options).length}\n`);
    } else if (command === 'needs-reconcile' && settingsPath) {
      process.stdout.write(`${needsReconcile(path.resolve(settingsPath), options) ? 'yes' : 'no'}\n`);
    } else if (command === 'ensure' && settingsPath) {
      const result = ensureConfigured(path.resolve(settingsPath), options);
      process.stdout.write(`${result.changed ? 'changed' : result.state}\n`);
    } else {
      process.stderr.write('Usage: node bin/claude-hookify.js <state|missing-hooks|needs-reconcile|ensure> <settings.json> [--self-improvement] [--remove-trajectory]\n');
      process.exitCode = 2;
    }
  } catch (error) {
    process.stderr.write(`Error: ${error.message}\n`);
    process.exitCode = 2;
  }
}

module.exports = {
  HOOKIFY_PLUGIN_ID,
  CORE_HOOK_GROUPS: BASE_CORE_HOOK_GROUPS,
  TRAJECTORY_COMMAND,
  coreHookGroups,
  configuredState,
  ensureConfigured,
  localOverrideState,
  missingCoreHooks,
  needsReconcile,
  readSettings,
};
