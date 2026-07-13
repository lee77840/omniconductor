# One-time, vendor-neutral model routing

CONDUCTOR keeps **task difficulty** stable and lets each installed tool translate
that difficulty to its own native model controls. The detailed Tier triggers in
`core/universal-rules/meta-discipline.md` remain authoritative; setup never changes
them.

## First installation

The recommended entry point is interactive:

```bash
npx omniconductor init --target=all .
```

Before emitting any role file, the CLI shows one summary for the installed
adapters and asks whether to accept all recommendations. If the user chooses
`customize`, only the selected adapter asks for three values: Tier 1, Tier 2,
and Tier 3. Named roles do not ask separately; they inherit the saved Tier.

The project-local selection is saved atomically in
`.conductor/model-routing.json`. Reinstall and update reuse it without asking.
To inspect or change it later:

```bash
npx omniconductor models show .
npx omniconductor models configure --target=codex .
npx omniconductor models configure --target=all . --force
```

`--force` is explicit replacement after reviewing an invalid or obsolete file;
normal installs never silently repair or downgrade a user selection.

## Recommended mappings

| Adapter | Tier 1 — conceptual/complex | Tier 2 — routine | Tier 3 — trivial | Enforcement |
|---|---|---|---|---|
| Claude Code | `opus` | `sonnet` | `haiku` | Native agent model |
| Codex | `gpt-5.6-sol` + `high` | `gpt-5.6-terra` + `medium` | `gpt-5.6-luna` + `low` | Native agent model + reasoning effort |
| Gemini CLI | `pro` | `flash` | `flash-lite` | Native agent model |
| Cursor | `gpt-5.6-sol` | `gpt-5.6-terra` | `gpt-5.6-luna` | Native agent model; provider fallback remains possible |
| GitHub Copilot | `gpt-5.6-sol` | `gpt-5.6-terra` | `gpt-5.6-luna` | Native agent model; account/policy remains authoritative |
| Windsurf | `adaptive` | `adaptive` | `adaptive` | Advisory session requirement only |

Claude and Gemini recommendations use provider semantic/family aliases. Codex is
checked against the local CLI binary's bundled-model catalog, which proves binary
recognition rather than account/plan availability. Cursor is checked against its
local provider/account catalog when a safe supported CLI catalog is available.
Copilot availability can vary by plan, client, and
organization policy, so a syntactically valid saved choice is not represented as
account-verified when no catalog is exposed. `doctor` reports this distinction.

Windsurf workflows have no model field and expose no project API for reading the
current Cascade selector. CONDUCTOR therefore writes an explicit “select
Adaptive” preflight to every role workflow and records enforcement as
`advisory-session`; it never reports this as an automatic pin.

## Non-interactive and CI behavior

An unconfigured role-emitting install with `--no-prompt` fails before writing
managed output. CI must make the choice explicit:

```bash
npx omniconductor init --target=all . --no-prompt --accept-model-defaults
```

Alternatively, commit/provision a reviewed `.conductor/model-routing.json`
before installation. `--dry-run` may preview recommendations without creating
the file. `recipes-only` does not emit roles and therefore does not require model
setup.

## Local adapter wrapper and manual-copy fallback

Calling `adapters/<tool>/transform.sh` directly is a local wrapper around the
same Node CLI transaction. It requires Node.js and delegates to
`omniconductor init --target=<tool>` before any role emission, so the same
one-time Tier summary, explicit choice, atomic project save, and reinstall reuse
apply to both public install commands. The wrapper's internal adapter-child mode
exists only to prevent recursion after the CLI has completed setup; it is not a
separate user-facing installation path.

Only fully manual file-copy installation bypasses that transaction. The
universal first-use gate remains as defense in depth for such manually copied or
legacy role files: if `.conductor/model-routing.json` is absent, role dispatch
pauses and asks the user to run `omniconductor models configure`.

Hooks and instruction files cannot portably capture a structured answer, write
all role files, and hot-reload the role registry in the same original prompt on
all six tools. When a tool does not document hot reload, the main thread may
continue the original task, but newly generated role routing starts after the
documented reload or next session.

## Safety and lifecycle

- Values are parsed as JSON data and passed through process environments; they
  are never evaluated as shell code. Before every real role-emitting write, each
  adapter reloads the validated project file and replaces inherited environment
  values with that saved mapping; environment variables are not a configuration
  or authorization boundary.
- Validators reject control characters, unsafe syntax, links, and hard-linked
  configuration files.
- Configuration and installed role changes share one project lock. Reconfiguration
  verifies manifest ownership and current checksums, journals old role/manifest/config
  bytes, writes config last, and restores the last complete state on failure. A real
  install holds that same lock through adapter and manifest writes (including
  cross-mode recipes-only updates), so concurrent `models configure` cannot commit a
  mixed revision. Doctor decides whether routing is required from actual managed role
  ownership, not from the latest mode label alone.
- A dead-process lock is reclaimed only after age and PID checks. A surviving crash
  journal is recovered before retry; concurrent initial or installed reconfiguration
  converges on complete revisions without mixed role/config state.
- Managed parents, leaves, backups, and manifests are containment-checked with
  `lstat`; symlinks, hardlinks, special files, traversal, absolute paths, and paths
  outside an adapter's declared surface are refused before mutation.
- The config contains no prompt text, credentials, or API keys.
- Uninstall removes generated runtime files but retains adopter model choices so
  a later reinstall does not ask again.
- A provider retirement or policy rejection requires explicit reconfiguration;
  CONDUCTOR never silently maps the task to a lower Tier.

## Primary provider contracts

- [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) and
  [model configuration](https://code.claude.com/docs/en/model-config)
- [OpenAI model catalog](https://developers.openai.com/api/docs/models)
- [Gemini CLI reference](https://geminicli.com/docs/cli/cli-reference/)
- [GitHub Copilot supported models](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
  and [CLI model options](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- [Cursor subagents](https://cursor.com/docs/subagents.md) and
  [CLI parameters](https://docs.cursor.com/en/cli/reference/parameters)
- [Windsurf workflows](https://docs.windsurf.com/windsurf/cascade/workflows) and
  [Cascade](https://docs.windsurf.com/windsurf/cascade/cascade)
