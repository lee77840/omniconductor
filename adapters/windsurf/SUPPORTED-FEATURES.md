# Windsurf — supported features

Detailed matrix of which CONDUCTOR features Windsurf supports.

## Feature support

| Feature | Windsurf support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `.windsurfrules` at project root | Auto-loaded on session start. |
| **Directory-based rule loading** | ✅ Native | `.devin/rules/*.md` | All files in directory load together. No per-pattern scoping. Legacy `.windsurf/rules/` still read. |
| **In-IDE chat / completion** | ✅ Native | Windsurf's primary feature | Similar to Cursor. |
| **Per-pattern rule scoping** | ⚠️ Directory-based only | — | Whole `.devin/rules/` directory loads; no per-file glob filtering. |
| **Sub-agent dispatch** | ✅ Native (2026) | Cascade sub-agent dispatch | See `docs/COMPATIBILITY-MATRIX.md` / ADR-031. CONDUCTOR ships the reflector as a manual rule (`.devin/rules/reflector.md`) rather than a named agent file. |
| **Hooks** | ✅ Native (2026) | `.windsurf/hooks.json` | ADR-031. No session-start/stop hook event — CONDUCTOR uses `post_cascade_response_with_transcript` instead. Only the Reflector hook is emitted today (ADR-032); broader hook-set emission is Phase 2. |
| **Per-task model routing** | ✅ Native (2026) | Per-task model selection | ADR-031. |
| **Custom slash commands** | ✅ Native (2026) | Workflows at `.windsurf/workflows/*.md` | ADR-031. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Read on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text reminds | Self-policed. |
| **Two-stage code review enforcement** | ❌ rule reminder only | | |

## Universal-rule → Windsurf translation

For each `core/universal-rules/<rule>.md`:

1. Parse YAML front-matter.
2. If `always_loaded: true` → APPEND content (sans front-matter) to `.windsurfrules`.
3. Else → write `.devin/rules/<rule>.md` (preferred dir; legacy `.windsurf/rules/` still read) (front-matter STRIPPED — Windsurf doesn't use it for filtering).
4. Tool-specific callouts:
   - `> **Windsurf-only mechanism**` (rare): keep.
   - `> **Claude-only mechanism**`: REPLACE with `> **Note (Windsurf)**: enforced by hook on Claude Code; on Windsurf, follow self-policed.`
   - Other tool callouts: STRIP.

## Strengths to lean into

- Always-loaded baseline + grouped rules directory is a natural fit for the universal-rules collection.
- In-IDE experience similar to Cursor — many of the same UX wins.

## Weaknesses to acknowledge

- Lack of per-pattern scoping means `coding-conventions.md` loads even when editing a `README.md`. Acceptable; just adds a small context cost per session.
- Hooks are now natively supported (`.windsurf/hooks.json` — see `docs/COMPATIBILITY-MATRIX.md` / ADR-031), but Windsurf has no session-start/stop hook event; CONDUCTOR uses `post_cascade_response_with_transcript` as the closest equivalent. CONDUCTOR currently emits only the self-improvement Reflector hook (ADR-032); broader hook-set emission (commit-blocking, spec enforcement) is Phase 2 — until then, pair with a git pre-commit hook for mechanical enforcement.

## Adapter status

- ✅ `transform.sh` implemented — emits `.windsurfrules` (always-loaded baseline), `.devin/rules/*.md` (5 universal rules + opt-in recipes, front-matter stripped; legacy `.windsurf/rules/` still read), and `docs/*`. Supports `--recipes=`, `--dry-run`, `--no-prompt`, `--uninstall`/`--force`, `--help`. Writes a `.conductor-manifest.json` for clean rollback.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Windsurf adapter emits the Reflector loop (ADR-032):

- **Hook**: `.windsurf/hooks.json` — registers `.conductor/reflect/trajectory-log.sh` on the `post_cascade_response_with_transcript` event (Windsurf has no session-start/stop event; this is the closest equivalent). Written only if no hook config exists; if one is already present, the adapter emits a manual-merge log entry instead of overwriting.
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
