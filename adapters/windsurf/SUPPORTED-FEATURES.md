# Windsurf — supported features

Detailed matrix of which CONDUCTOR features Windsurf supports.

## Feature support

| Feature | Windsurf support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `.windsurfrules` at project root | Auto-loaded on session start. |
| **Directory-based rule loading** | ✅ Native | `.windsurf/rules/*.md` | All files in directory load together. No per-pattern scoping. |
| **In-IDE chat / completion** | ✅ Native | Windsurf's primary feature | Similar to Cursor. |
| **Per-pattern rule scoping** | ⚠️ Directory-based only | — | Whole `.windsurf/rules/` directory loads; no per-file glob filtering. |
| **Sub-agent dispatch** | ❌ | — | Single chat per task. |
| **Hooks** | ❌ | — | |
| **Per-call model routing** | ❌ | — | |
| **Custom slash commands** | ❌ | — | |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Read on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text reminds | Self-policed. |
| **Two-stage code review enforcement** | ❌ rule reminder only | | |

## Universal-rule → Windsurf translation

For each `core/universal-rules/<rule>.md`:

1. Parse YAML front-matter.
2. If `always_loaded: true` → APPEND content (sans front-matter) to `.windsurfrules`.
3. Else → write `.windsurf/rules/<rule>.md` (front-matter STRIPPED — Windsurf doesn't use it for filtering).
4. Tool-specific callouts:
   - `> **Windsurf-only mechanism**` (rare): keep.
   - `> **Claude-only mechanism**`: REPLACE with `> **Note (Windsurf)**: enforced by hook on Claude Code; on Windsurf, follow self-policed.`
   - Other tool callouts: STRIP.

## Strengths to lean into

- Always-loaded baseline + grouped rules directory is a natural fit for the universal-rules collection.
- In-IDE experience similar to Cursor — many of the same UX wins.

## Weaknesses to acknowledge

- Lack of per-pattern scoping means `coding-conventions.md` loads even when editing a `README.md`. Acceptable; just adds a small context cost per session.
- Lack of hooks means no commit-blocking. Pair with a git pre-commit hook for mechanical enforcement.

## Adapter status

- ✅ `transform.sh` implemented — emits `.windsurfrules` (always-loaded baseline), `.windsurf/rules/*.md` (5 universal rules + opt-in recipes, front-matter stripped), and `docs/*`. Supports `--recipes=`, `--dry-run`, `--no-prompt`, `--uninstall`/`--force`, `--help`. Writes a `.conductor-manifest.json` for clean rollback.

## Verification

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `transform.sh` emits baseline + grouped rules + docs | ✅ implemented | `bash adapters/windsurf/transform.sh <target> --no-prompt` then inspect tree. |
| `.windsurfrules` auto-loads | ⏳ P3.5 | Open project in Windsurf; verify rule indicator. |
| `.windsurf/rules/*.md` auto-loads | ⏳ P3.5 | Verify rule indicator includes all files in directory. |
