#!/usr/bin/env node
'use strict';

/*
 * Read-only extension/MCP trust audit (ADR-060).
 *
 * The auditor only inspects provider project configuration declared by adapter
 * metadata. It never follows symlinks, executes commands, opens network
 * connections, reads user-home configuration, or returns credential values.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode'];
const MAX_FILE_BYTES = 1024 * 1024;
const MAX_DEPTH = 5;
const CANDIDATE_NAMES = new Set([
  '.mcp.json',
  'mcp.json',
  'mcp_config.json',
  'plugin.json',
  'gemini-extension.json',
  'marketplace.json',
  'settings.json',
  'settings.local.json',
  'config.toml',
  'hooks.json',
  'opencode.json',
]);
const SECRET_KEY = /(^|[_-])(api[_-]?key|token|secret|password|authorization|bearer)([_-]|$)/i;
const URL_KEY = /(url|uri|endpoint)$/i;
const NETWORK_KEY = /(allowed.*(domain|host)|network|domains|hosts)$/i;

function isSafeRelative(value) {
  if (typeof value !== 'string' || !value || path.isAbsolute(value) || value.includes('\0')) return false;
  const normalized = path.posix.normalize(value.replace(/\\/g, '/'));
  return normalized !== '..' && !normalized.startsWith('../');
}

function validateExtensionTrustMetadata(metadata) {
  const contract = metadata && metadata.extension_trust;
  const problems = [];
  if (!contract || typeof contract !== 'object') return ['extension_trust is required'];
  if (contract.schema_version !== 1) problems.push('schema_version must be 1');
  if (!Array.isArray(contract.audit_roots) || !contract.audit_roots.length) {
    problems.push('audit_roots must be a non-empty array');
  } else {
    for (const root of contract.audit_roots) {
      if (!isSafeRelative(root)) problems.push(`unsafe audit root: ${String(root)}`);
    }
  }
  if (!Array.isArray(contract.native_controls) || !contract.native_controls.length) {
    problems.push('native_controls must be a non-empty array');
  }
  if (!['verified', 'verification-required'].includes(contract.mcp_protocol_2026_07_28)) {
    problems.push('mcp_protocol_2026_07_28 must be verified|verification-required');
  }
  if (!Array.isArray(contract.sources) || !contract.sources.length) {
    problems.push('sources must be a non-empty array');
  } else {
    for (const source of contract.sources) {
      if (!source || typeof source.url !== 'string' || !/^https:\/\//.test(source.url)) {
        problems.push('every source needs an https url');
      }
      if (!source || !/^\d{4}-\d{2}-\d{2}$/.test(source.checked || '')) {
        problems.push('every source needs checked=YYYY-MM-DD');
      }
    }
  }
  return problems;
}

function loadMetadata(tool) {
  const file = path.join(ROOT, 'adapters', tool, 'metadata.json');
  const metadata = JSON.parse(fs.readFileSync(file, 'utf8'));
  const problems = validateExtensionTrustMetadata(metadata);
  if (problems.length) throw new Error(`${tool} metadata: ${problems.join('; ')}`);
  return metadata;
}

function finding(severity, code, file, message, keyPath) {
  const item = { severity, code, file, message };
  if (keyPath) item.key_path = keyPath;
  return item;
}

function placeholderValue(value) {
  if (typeof value !== 'string' || !value.trim()) return true;
  const trimmed = value.trim();
  return /^\$\{?[A-Z][A-Z0-9_]*\}?$/.test(trimmed)
    || /^<[^>]+>$/.test(trimmed)
    || /^env:/i.test(trimmed)
    || /process\.env\./.test(trimmed)
    || /\$\{(?:env:)?[A-Z][A-Z0-9_]*\}/.test(trimmed);
}

function packageIsPinned(value) {
  if (typeof value !== 'string') return false;
  const at = value.lastIndexOf('@');
  if (at <= 0) return false;
  const selector = value.slice(at + 1);
  return /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(selector)
    || /^[0-9a-f]{7,40}$/i.test(selector);
}

function inspectCommand(node, file, keyPath, findings) {
  if (!node || typeof node !== 'object' || Array.isArray(node) || typeof node.command !== 'string') return;
  const command = node.command.trim();
  const args = Array.isArray(node.args) ? node.args.filter((arg) => typeof arg === 'string') : [];
  if (/^(npx|uvx|bunx)$/.test(command)) {
    const packageArg = args.find((arg) => !arg.startsWith('-'));
    if (!packageIsPinned(packageArg)) {
      findings.push(finding(
        'WARN', 'UNPINNED_EXECUTOR', file,
        `${command} launches a package without an exact version or commit pin`, `${keyPath}.command`,
      ));
    }
  }
  if (/^(sh|bash|zsh)$/.test(command) && args.some((arg) => arg === '-c')) {
    findings.push(finding(
      'HIGH', 'SHELL_COMMAND_STRING', file,
      'MCP or plugin configuration delegates execution to a shell command string', `${keyPath}.command`,
    ));
  }
  if (/\b(curl|wget)\b/.test(command)) {
    findings.push(finding(
      'HIGH', 'NETWORK_BOOTSTRAP_COMMAND', file,
      'configuration launches a network bootstrap command', `${keyPath}.command`,
    ));
  }
}

function inspectObject(node, file, keyPath, findings) {
  if (Array.isArray(node)) {
    node.forEach((value, index) => inspectObject(value, file, `${keyPath}[${index}]`, findings));
    return;
  }
  if (!node || typeof node !== 'object') return;

  inspectCommand(node, file, keyPath, findings);
  if (node.source && typeof node.source === 'object' && typeof node.source.url === 'string'
      && !node.source.ref && !node.source.sha) {
    findings.push(finding(
      'WARN', 'UNPINNED_PLUGIN_SOURCE', file,
      'plugin source URL has no immutable sha or explicit ref selector', `${keyPath}.source`,
    ));
  }

  for (const [key, value] of Object.entries(node)) {
    const childPath = keyPath ? `${keyPath}.${key}` : key;
    if (SECRET_KEY.test(key) && typeof value === 'string' && !placeholderValue(value)) {
      findings.push(finding(
        'HIGH', 'INLINE_SECRET', file,
        'credential-like field contains a literal value; the value was redacted', childPath,
      ));
    }
    if (URL_KEY.test(key) && typeof value === 'string') {
      if (/^http:\/\//i.test(value)) {
        findings.push(finding('HIGH', 'PLAINTEXT_REMOTE_URL', file, 'remote endpoint uses plaintext HTTP', childPath));
      }
      if (/\/sse\/?(?:[?#].*)?$/i.test(value)) {
        findings.push(finding('WARN', 'LEGACY_SSE_TRANSPORT', file, 'endpoint appears to use the deprecated legacy SSE transport', childPath));
      }
    }
    if (/transport/i.test(key) && typeof value === 'string' && /^sse$/i.test(value)) {
      findings.push(finding('WARN', 'LEGACY_SSE_TRANSPORT', file, 'transport is explicitly configured as legacy SSE', childPath));
    }
    if (NETWORK_KEY.test(key) && (value === '*' || (Array.isArray(value) && value.includes('*')))) {
      findings.push(finding('WARN', 'UNBOUNDED_NETWORK_SCOPE', file, 'network policy contains a wildcard scope', childPath));
    }
    inspectObject(value, file, childPath, findings);
  }
}

function textFindings(text, file) {
  const findings = [];
  const lines = text.split(/\r?\n/);
  lines.forEach((line, index) => {
    const lineNo = index + 1;
    if (/^\s*(api[_-]?key|token|secret|password|authorization|bearer)\s*=\s*["']?[^$<{\s][^\s]*/i.test(line)) {
      findings.push(finding(
        'HIGH', 'INLINE_SECRET', file,
        `credential-like assignment contains a literal value; value redacted (line ${lineNo})`,
      ));
    }
    if (/^\s*(command|cmd)\s*=\s*["']?(sh|bash|zsh)\b/i.test(line) && /\s-c\b/.test(line)) {
      findings.push(finding('HIGH', 'SHELL_COMMAND_STRING', file, `shell command string configured (line ${lineNo})`));
    }
    if (/^\s*(url|endpoint)\s*=\s*["']?http:\/\//i.test(line)) {
      findings.push(finding('HIGH', 'PLAINTEXT_REMOTE_URL', file, `remote endpoint uses plaintext HTTP (line ${lineNo})`));
    }
    if (/\/sse\/?["']?\s*$/i.test(line)) {
      findings.push(finding('WARN', 'LEGACY_SSE_TRANSPORT', file, `endpoint appears to use legacy SSE (line ${lineNo})`));
    }
  });
  return findings;
}

function inspectFile(targetAbs, absolute, relative) {
  const stat = fs.lstatSync(absolute);
  if (stat.isSymbolicLink()) {
    return { file: relative, findings: [finding('WARN', 'SYMLINK_SKIPPED', relative, 'symlinked configuration was not followed')] };
  }
  if (stat.isFile() && stat.nlink !== 1) {
    return { file: relative, findings: [finding('WARN', 'HARDLINK_SKIPPED', relative, 'hard-linked configuration was not read')] };
  }
  if (!stat.isFile()) return { file: relative, findings: [] };
  if (stat.size > MAX_FILE_BYTES) {
    return { file: relative, findings: [finding('WARN', 'FILE_TOO_LARGE', relative, `configuration exceeds ${MAX_FILE_BYTES} bytes and was skipped`)] };
  }
  const text = fs.readFileSync(absolute, 'utf8');
  const findings = [];
  if (relative.endsWith('.json')) {
    try { inspectObject(JSON.parse(text), relative, '', findings); }
    catch {
      findings.push(finding('HIGH', 'INVALID_JSON', relative, 'configuration is not valid JSON'));
    }
  } else {
    findings.push(...textFindings(text, relative));
  }
  return { file: relative, findings };
}

function discoverEntry(targetAbs, entry) {
  const start = path.resolve(targetAbs, entry);
  const relStart = path.relative(targetAbs, start).replace(/\\/g, '/');
  if (relStart === '..' || relStart.startsWith('../') || path.isAbsolute(relStart)) return [];
  if (!fs.existsSync(start)) return [];
  const startStat = fs.lstatSync(start);
  if (startStat.isSymbolicLink() || startStat.isFile()) return [{ absolute: start, relative: relStart || path.basename(start) }];
  if (!startStat.isDirectory()) return [];

  const files = [];
  const walk = (directory, depth) => {
    if (depth > MAX_DEPTH) return;
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name));
    for (const item of entries) {
      const absolute = path.join(directory, item.name);
      const relative = path.relative(targetAbs, absolute).replace(/\\/g, '/');
      if (item.isSymbolicLink()) {
        if (CANDIDATE_NAMES.has(item.name)) files.push({ absolute, relative });
      } else if (item.isDirectory()) {
        walk(absolute, depth + 1);
      } else if (item.isFile() && CANDIDATE_NAMES.has(item.name)) {
        files.push({ absolute, relative });
      }
    }
  };
  walk(start, 0);
  return files;
}

function auditAdapter(targetAbs, tool) {
  const metadata = loadMetadata(tool);
  const contract = metadata.extension_trust;
  const discovered = new Map();
  for (const entry of contract.audit_roots) {
    for (const file of discoverEntry(targetAbs, entry)) discovered.set(file.relative, file);
  }
  const inspected = [...discovered.values()]
    .sort((a, b) => a.relative.localeCompare(b.relative))
    .map((file) => inspectFile(targetAbs, file.absolute, file.relative));
  const findings = inspected.flatMap((item) => item.findings);
  if (inspected.some((item) => /(^|\/)(\.mcp\.json|mcp\.json|mcp_config\.json)$/.test(item.file))
      && contract.mcp_protocol_2026_07_28 === 'verification-required') {
    findings.push(finding(
      'WARN', 'MCP_PROTOCOL_VERIFICATION_REQUIRED', '(adapter contract)',
      `${metadata.display_name} has no verified MCP 2026-07-28 protocol boundary in CONDUCTOR metadata`,
    ));
  }
  return {
    tool,
    display_name: metadata.display_name,
    native_controls: [...contract.native_controls],
    mcp_protocol_2026_07_28: contract.mcp_protocol_2026_07_28,
    inspected_files: inspected.map((item) => item.file),
    findings,
  };
}

function audit(targetDir, tools = TOOLS) {
  const targetAbs = path.resolve(targetDir);
  if (!fs.existsSync(targetAbs)) {
    throw new Error(`target directory does not exist: ${targetAbs}`);
  }
  const targetStat = fs.lstatSync(targetAbs);
  if (targetStat.isSymbolicLink() || !targetStat.isDirectory()) {
    throw new Error(`target must be a real directory, not a symlink or special file: ${targetAbs}`);
  }
  const targetRoot = fs.realpathSync(targetAbs);
  const adapters = tools.map((tool) => auditAdapter(targetRoot, tool));
  const counts = { HIGH: 0, WARN: 0 };
  for (const adapter of adapters) {
    for (const item of adapter.findings) counts[item.severity] += 1;
  }
  return {
    schema_version: 1,
    target: targetRoot,
    read_only: true,
    secret_values_included: false,
    summary: {
      adapters: adapters.length,
      inspected_files: new Set(adapters.flatMap((adapter) => adapter.inspected_files)).size,
      high: counts.HIGH,
      warnings: counts.WARN,
    },
    adapters,
  };
}

function render(report) {
  const lines = [
    `CONDUCTOR extension/MCP trust audit (read-only): ${report.target}`,
    `Inspected ${report.summary.inspected_files} unique configuration file(s); ${report.summary.high} high, ${report.summary.warnings} warning(s).`,
  ];
  for (const adapter of report.adapters) {
    lines.push(`\n[${adapter.display_name}] protocol-2026-07-28=${adapter.mcp_protocol_2026_07_28}; files=${adapter.inspected_files.length}`);
    if (!adapter.findings.length) lines.push('  OK — no configured risk pattern detected.');
    for (const item of adapter.findings) {
      lines.push(`  ${item.severity} ${item.code} ${item.file}${item.key_path ? ` (${item.key_path})` : ''}: ${item.message}`);
    }
  }
  lines.push('\nNo commands were executed, no symlinks were followed, and no credential values are included.');
  return lines.join('\n');
}

module.exports = {
  TOOLS,
  audit,
  render,
  validateExtensionTrustMetadata,
};
