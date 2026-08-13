#!/usr/bin/env node
'use strict';

/*
 * Schema-aware native hook configuration composer (ADR-056).
 *
 * This module only reads/writes the named JSON config. It never executes a
 * provider CLI or a hook. Existing user entries are preserved; only handlers
 * whose executable command exactly matches a registry-rendered CONDUCTOR
 * command are replaced.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const REGISTRY_PATH = path.join(ROOT, 'core', 'hooks', 'registry.json');
const ADAPTERS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode'];
const SHAPES = new Set(['flat', 'nested', 'plugin']);
const FEATURES = new Set(['baseline', 'self-improvement', 'output-cap', 'loop-engineering', 'git-hygiene']);

function isObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function readRegistry(registryPath = REGISTRY_PATH) {
  let registry;
  try {
    registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  } catch (error) {
    throw new Error(`${registryPath} is not valid JSON: ${error.message}`);
  }
  const problems = validateRegistry(registry);
  if (problems.length) throw new Error(`invalid hook registry: ${problems.join('; ')}`);
  return registry;
}

function validateRegistry(registry) {
  const problems = [];
  const at = (condition, message) => { if (!condition) problems.push(message); };
  at(isObject(registry), 'root must be an object');
  if (!isObject(registry)) return problems;
  at(registry.schema_version === 1, 'schema_version must be 1');
  at(isObject(registry.adapters), 'adapters must be an object');
  at(Array.isArray(registry.registrations), 'registrations must be an array');
  if (!isObject(registry.adapters) || !Array.isArray(registry.registrations)) return problems;

  for (const adapter of ADAPTERS) {
    const config = registry.adapters[adapter];
    at(isObject(config), `adapters.${adapter} must be an object`);
    if (!isObject(config)) continue;
    at(typeof config.config_path === 'string' && config.config_path.length > 0,
      `adapters.${adapter}.config_path must be non-empty`);
    at(SHAPES.has(config.shape), `adapters.${adapter}.shape must be flat|nested|plugin`);
    at(config.root_defaults === undefined || isObject(config.root_defaults),
      `adapters.${adapter}.root_defaults must be an object`);
  }

  const ids = new Set();
  for (const [index, registration] of registry.registrations.entries()) {
    const prefix = `registrations[${index}]`;
    at(isObject(registration), `${prefix} must be an object`);
    if (!isObject(registration)) continue;
    at(typeof registration.id === 'string' && /^[a-z0-9-]+$/.test(registration.id),
      `${prefix}.id must be lowercase hyphenated`);
    if (typeof registration.id === 'string') {
      at(!ids.has(registration.id), `${prefix}.id duplicates '${registration.id}'`);
      ids.add(registration.id);
    }
    at(typeof registration.source === 'string' && registration.source.length > 0,
      `${prefix}.source must be non-empty`);
    if (typeof registration.source === 'string') {
      at(fs.existsSync(path.join(ROOT, registration.source)),
        `${prefix}.source does not exist: ${registration.source}`);
    }
    at(FEATURES.has(registration.feature), `${prefix}.feature is unsupported`);
    at(typeof registration.intent === 'string' && registration.intent.length > 0,
      `${prefix}.intent must be non-empty`);
    at(typeof registration.fallback === 'string' && registration.fallback.length > 0,
      `${prefix}.fallback must be non-empty`);
    at(isObject(registration.targets) && Object.keys(registration.targets).length > 0,
      `${prefix}.targets must be a non-empty object`);
    if (!isObject(registration.targets)) continue;
    for (const [adapter, target] of Object.entries(registration.targets)) {
      at(ADAPTERS.includes(adapter), `${prefix}.targets.${adapter} is unknown`);
      at(isObject(target), `${prefix}.targets.${adapter} must be an object`);
      if (!ADAPTERS.includes(adapter) || !isObject(target)) continue;
      at(typeof target.event === 'string' && target.event.length > 0,
        `${prefix}.targets.${adapter}.event must be non-empty`);
      const shape = registry.adapters[adapter] && registry.adapters[adapter].shape;
      if (shape === 'flat' || shape === 'plugin') {
        at(isObject(target.handler), `${prefix}.targets.${adapter}.handler must be an object`);
        if (isObject(target.handler)) {
          at(commandValues(target.handler).length > 0,
            `${prefix}.targets.${adapter}.handler must declare an executable command`);
        }
        at(target.group === undefined, `${prefix}.targets.${adapter} cannot use group for ${shape} shape`);
      } else if (shape === 'nested') {
        at(isObject(target.group) && Array.isArray(target.group.hooks),
          `${prefix}.targets.${adapter}.group.hooks must be an array`);
        if (isObject(target.group) && Array.isArray(target.group.hooks)) {
          target.group.hooks.forEach((handler, handlerIndex) => {
            at(isObject(handler),
              `${prefix}.targets.${adapter}.group.hooks[${handlerIndex}] must be an object`);
            if (isObject(handler)) {
              at(commandValues(handler).length > 0,
                `${prefix}.targets.${adapter}.group.hooks[${handlerIndex}] must declare an executable command`);
            }
          });
        }
        at(target.handler === undefined, `${prefix}.targets.${adapter} cannot use handler for nested shape`);
      }
    }
  }

  for (const id of ['commit-current-work', 'commit-test-coverage', 'review-before-stop']) {
    at(ids.has(id), `required portable policy '${id}' is missing`);
  }
  return problems;
}

function readConfig(configPath) {
  if (!fs.existsSync(configPath)) return {};
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    throw new Error(`${configPath} is not valid JSON: ${error.message}`);
  }
  if (!isObject(parsed)) throw new Error(`${configPath} must contain a JSON object`);
  if (parsed.hooks !== undefined && !isObject(parsed.hooks)) {
    throw new Error(`${configPath} hooks must be a JSON object`);
  }
  return parsed;
}

function commandValues(handler) {
  if (!isObject(handler)) return [];
  return ['command', 'bash', 'powershell']
    .map((key) => handler[key])
    .filter((value) => typeof value === 'string' && value.trim().length > 0);
}

function isOwnedHandler(handler, ownedCommands) {
  return commandValues(handler).some((command) => ownedCommands.has(command));
}

function ownedCommandsForAdapter(registry, adapter) {
  const commands = new Set();
  for (const registration of registry.registrations) {
    const target = registration.targets[adapter];
    if (!target) continue;
    if (target.handler) {
      for (const command of commandValues(target.handler)) commands.add(command);
    }
    if (target.group) {
      for (const handler of target.group.hooks) {
        for (const command of commandValues(handler)) commands.add(command);
      }
    }
  }
  return commands;
}

function selectedTargets(registry, adapter, features) {
  const selected = [];
  for (const registration of registry.registrations) {
    if (!features.has(registration.feature)) continue;
    const target = registration.targets[adapter];
    if (target) selected.push({ id: registration.id, ...deepClone(target) });
  }
  return selected;
}

function validateEventArrays(settings, adapterConfig, configPath) {
  if (!settings.hooks) return;
  for (const [event, value] of Object.entries(settings.hooks)) {
    if (!Array.isArray(value)) {
      throw new Error(`${configPath} hooks.${event} must be an array`);
    }
    if (adapterConfig.shape === 'nested') {
      for (const [index, group] of value.entries()) {
        if (!isObject(group)) throw new Error(`${configPath} hooks.${event}[${index}] must be an object`);
        if (!Array.isArray(group.hooks)) {
          throw new Error(`${configPath} hooks.${event}[${index}].hooks must be an array`);
        }
      }
    } else {
      for (const [index, handler] of value.entries()) {
        if (!isObject(handler)) throw new Error(`${configPath} hooks.${event}[${index}] must be an object`);
      }
    }
  }
}

function removeOwned(settings, adapterConfig, ownedCommands) {
  if (!settings.hooks) return;
  for (const event of Object.keys(settings.hooks)) {
    if (adapterConfig.shape === 'flat') {
      settings.hooks[event] = settings.hooks[event]
        .filter((handler) => !isOwnedHandler(handler, ownedCommands));
    } else {
      const groups = [];
      for (const group of settings.hooks[event]) {
        const next = deepClone(group);
        next.hooks = next.hooks
          .filter((handler) => !isOwnedHandler(handler, ownedCommands));
        if (next.hooks.length) groups.push(next);
      }
      settings.hooks[event] = groups;
    }
    if (!settings.hooks[event].length) delete settings.hooks[event];
  }
}

function composeConfig(registry, adapter, input, featureNames, configPath = '<config>') {
  if (!ADAPTERS.includes(adapter)) throw new Error(`unknown adapter '${adapter}'`);
  if (!isObject(input)) throw new Error(`${configPath} must contain a JSON object`);
  const features = new Set(featureNames);
  for (const feature of features) {
    if (!FEATURES.has(feature)) throw new Error(`unknown hook feature '${feature}'`);
  }

  const adapterConfig = registry.adapters[adapter];
  if (adapterConfig.shape === 'plugin') {
    throw new Error(`${adapter} uses a source-verified native plugin, not JSON hook composition`);
  }
  const settings = deepClone(input);
  validateEventArrays(settings, adapterConfig, configPath);
  for (const [key, value] of Object.entries(adapterConfig.root_defaults || {})) {
    if (settings[key] === undefined) settings[key] = deepClone(value);
    else if (key === 'version' && settings[key] !== value) {
      throw new Error(`${configPath} version must be ${value}`);
    }
  }
  settings.hooks = settings.hooks || {};
  removeOwned(settings, adapterConfig, ownedCommandsForAdapter(registry, adapter));

  for (const target of selectedTargets(registry, adapter, features)) {
    settings.hooks[target.event] = settings.hooks[target.event] || [];
    if (adapterConfig.shape === 'flat') settings.hooks[target.event].push(target.handler);
    else settings.hooks[target.event].push(target.group);
  }
  return settings;
}

function parseFeatures(value) {
  if (!value) return [];
  return value.split(',').map((item) => item.trim()).filter(Boolean);
}

function writeAtomic(configPath, output) {
  const dir = path.dirname(configPath);
  fs.mkdirSync(dir, { recursive: true });
  const existed = fs.existsSync(configPath);
  const mode = existed ? (fs.statSync(configPath).mode & 0o777) : 0o644;
  const tempPath = path.join(dir, `.${path.basename(configPath)}.conductor-hook-${process.pid}.tmp`);
  try {
    fs.writeFileSync(tempPath, output, { mode, flag: 'wx' });
    if (process.env.CONDUCTOR_HOOK_COMPILER_FAIL_STAGE === 'before-rename') {
      throw new Error('injected failure before rename');
    }
    fs.renameSync(tempPath, configPath);
  } finally {
    try { fs.unlinkSync(tempPath); } catch { /* rename consumed it or write failed */ }
  }
}

function parseCli(argv) {
  const command = argv[0];
  const options = {};
  for (const arg of argv.slice(1)) {
    if (!arg.startsWith('--') || !arg.includes('=')) continue;
    const [key, ...rest] = arg.slice(2).split('=');
    options[key] = rest.join('=');
  }
  return { command, options };
}

function runCli(argv) {
  const { command, options } = parseCli(argv);
  const registry = readRegistry();
  if (command === 'validate') {
    process.stdout.write('OK — hook registry valid\n');
    return 0;
  }
  if (!['render', 'ensure'].includes(command) || !options.adapter || !options.config) {
    process.stderr.write('Usage: node bin/hook-config.js <validate|render|ensure> --adapter=<tool> --config=<path> [--features=a,b]\n');
    return 2;
  }
  const configPath = path.resolve(options.config);
  const current = readConfig(configPath);
  const next = composeConfig(registry, options.adapter, current, parseFeatures(options.features), configPath);
  const output = `${JSON.stringify(next, null, 2)}\n`;
  if (command === 'render') process.stdout.write(output);
  else {
    const before = fs.existsSync(configPath) ? fs.readFileSync(configPath, 'utf8') : null;
    if (before !== output) writeAtomic(configPath, output);
    process.stdout.write(before === output ? 'unchanged\n' : 'changed\n');
  }
  return 0;
}

if (require.main === module) {
  try {
    process.exitCode = runCli(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`hook-config: ${error.message}\n`);
    process.exitCode = 2;
  }
}

module.exports = {
  ADAPTERS,
  FEATURES,
  REGISTRY_PATH,
  composeConfig,
  isOwnedHandler,
  ownedCommandsForAdapter,
  parseFeatures,
  readConfig,
  readRegistry,
  selectedTargets,
  validateRegistry,
  writeAtomic,
};
