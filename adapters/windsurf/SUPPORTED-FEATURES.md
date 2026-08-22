# Windsurf — supported features

Detailed matrix of which CONDUCTOR features Windsurf supports.

## Feature support

| Feature | Windsurf support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `.windsurfrules` at project root | Auto-loaded on session start. |
| **Directory-based rule loading** | ✅ Native | `.devin/rules/*.md` | All files in directory load together. No per-pattern scoping. Legacy `.windsurf/rules/` still read. |
| **In-IDE chat / completion** | ✅ Native | Windsurf's primary feature | Similar to Cursor. |
| **Runtime compatibility diagnosis** | ✅ Offline | metadata `runtime_contract` + doctor D13 | Product lifecycle records Devin Desktop as canonical while retaining the stable Windsurf adapter identifier and legacy paths. |
| **Per-pattern rule scoping** | ⚠️ Directory-based only | — | Whole `.devin/rules/` directory loads; no per-file glob filtering. |
| **Role entry points** | ✅ Emitted workflows | Eight `.windsurf/workflows/*.md` files | Includes Tier 3 utility; no unverified project custom-agent profile contract is claimed. |
| **Hooks** | ✅ Native (2026) | `.windsurf/hooks.json` | CONDUCTOR uses the verified asynchronous `post_cascade_response_with_transcript` Reflector hook; it cannot continue the completed turn, so the three portable guards remain rule fallbacks. |
| **Per-task model routing** | ⚠️ Advisory-session | Cascade Adaptive selector | Setup saves Adaptive and workflows display a preflight; no workflow model field or selector-state API exists. |
| **Custom slash commands** | ✅ Native (2026) | Workflows at `.windsurf/workflows/*.md` | ADR-031. |
| **Portable Agent Skills** | ✅ Emitted | `.agents/skills/*/SKILL.md` | Devin's recommended path; automatic or `@skills:<name>` activation, with one active skill at a time. |
| **Skill proposal inbox** | ✅ Opt-in | `.agents/skills/propose-skill/SKILL.md` + `.conductor/skill-proposals/` | Emitted only with `self-improvement`; Devin suggestions may gather evidence, but acceptance never applies a skill. |
| **Extension/MCP trust audit** | ✅ Read-only | `omniconductor audit extensions --target=windsurf` | Scans bounded project-local Windsurf/Devin configuration while remote organization state remains provider-controlled. |
| **Provider package** | 📦 Direct fallback | no guessed manifest | `devin plugin` remains preview/policy-sensitive in the verified source; CONDUCTOR emits no speculative native manifest. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Read on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text reminds | Self-policed. |
| **Two-stage code review enforcement** | ❌ rule reminder only | | |
| **Tool-output cap (store-time)** | ❌ N/A | — | Windsurf's only verified hook is `post_cascade_response_with_transcript`, which fires after the full response — not a per-tool-call surface — so an individual tool result cannot be capped before it's stored. CONDUCTOR does not fake enforcement here. See ADR-051. |

## Universal-rule → Windsurf translation

For each `core/universal-rules/<rule>.md`:

1. Parse YAML front-matter.
2. If `always_loaded: true` → APPEND content (sans front-matter) to `.windsurfrules`.
3. Else → write `.devin/rules/<rule>.md` (preferred dir; legacy `.windsurf/rules/` still read) (front-matter STRIPPED — Windsurf doesn't use it for filtering).
4. Preserve capability-aware callouts from the universal source. Never rewrite a
   Claude + Codex shared guard as Claude-only, and never claim that Windsurf emits
   a local guard that the adapter does not install.

## Strengths to lean into

- A bounded `.windsurfrules` kernel plus complete `.devin/conductor/` references keeps the universal contract available without eager-loading it all.
- In-IDE experience similar to Cursor — many of the same UX wins.

## Weaknesses to acknowledge

- No verified per-pattern loader is claimed. Full installs route from the bounded kernel to exact references; compact `.devin/rules/` pointers are reserved for à-la-carte modes where selected policy must be active.
- Windsurf hooks are supported through `.windsurf/hooks.json`, but the verified post-response event cannot continue a completed turn. CONDUCTOR uses it for Reflector and native workflows for the eight roles; pair with Git/CI hooks for mechanical enforcement.
- The documented workflow format is prompt steps, not a per-workflow model manifest. Select Adaptive in Cascade; CONDUCTOR preserves Tier requirements in workflow text and never claims automatic enforcement.

## Adapter status

- ✅ `transform.sh` implemented — emits a bounded `.windsurfrules` kernel, byte-identical complete references under `.devin/conductor/`, à-la-carte pointers under `.devin/rules/`, and `docs/*`. Supports `--recipes=`, `--dry-run`, `--no-prompt`, `--uninstall`/`--force`, `--help`. Writes an adapter manifest for clean rollback.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Windsurf adapter emits the Reflector loop (ADR-032):

- **Hook**: `.windsurf/hooks.json` — schema-composes `.conductor/reflect/trajectory-log.sh` on `post_cascade_response_with_transcript`, preserving arbitrary existing user entries.
- **Command**: `.windsurf/workflows/reflect.md` — the `/reflect` workflow that distills the trajectory log into lesson candidates.
- **Rule**: `.devin/rules/reflector.md` — the reflector is shipped as a manual rule (not a named agent file) on Windsurf.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

Note: the adapter's rules now target `.devin/rules/` (the legacy `.windsurf/rules/` location is still read by Windsurf).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `transform.sh` emits baseline + grouped rules + docs | ✅ implemented | `bash adapters/windsurf/transform.sh <target> --no-prompt` then inspect tree. |
| `.windsurfrules` auto-loads | ⏳ P3.5 | Open project in Windsurf; verify rule indicator. |
| `.devin/rules/*.md` auto-loads | ⏳ P3.5 | Verify rule indicator includes all files in directory. |
