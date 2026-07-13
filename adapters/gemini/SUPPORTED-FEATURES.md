# Gemini CLI — supported features

Detailed matrix of which CONDUCTOR features Gemini CLI supports.

## Feature support

| Feature | Gemini support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `GEMINI.md` at project root | Auto-loaded by Gemini CLI on session start. |
| **Style guide convention** | ✅ Native | `.gemini/styleguide.md` | Coding-style-specific guide; complements GEMINI.md. |
| **Large-context capability** | ✅ Strength | Up to ~1M-2M tokens depending on Gemini Pro version | Bundled rule loading is no problem. |
| **Per-pattern rule scoping** | ❌ | — | All rules always-loaded. No per-file routing. |
| **Sub-agent dispatch** | ✅ Emitted | Eight named agents in `.gemini/agents/*.md` | Includes separate reviewer, code-reviewer, and Tier 3 utility roles. |
| **Hooks (SessionEnd etc.)** | ✅ Native (2026) | `hooks` block in `.gemini/settings.json` | CONDUCTOR emits the verified Reflector hook; other guard translations remain excluded until their contracts are verified. |
| **Per-task model routing** | ✅ Configured native (2026) | Agent `model` from saved Tier mapping | Recommended semantic aliases: `pro` / `flash` / `flash-lite`. |
| **Custom slash commands** | ✅ Native (2026) | `.gemini/commands/*.toml` | ADR-031. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Gemini reads on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text in `GEMINI.md` reminds user | Self-policed. |
| **Two-stage code review enforcement** | ❌ rule reminder only | | |

## Universal-rule → Gemini bundle translation

For each `core/universal-rules/<rule>.md`:

1. Strip front-matter (Gemini doesn't use it).
2. Concatenate body content into `GEMINI.md` as a section with heading `## <rule name>`.
3. Preserve capability-aware callouts from the universal source. Never rewrite a
   Claude + Codex shared guard as Claude-only, and never claim that Gemini emits
   a local guard that the adapter does not install.

## `.gemini/styleguide.md` content

Specifically the coding-conventions rule's body, formatted as a Gemini styleguide. Use Google's published styleguide format as inspiration if Gemini documents one.

## What Gemini DOES NOT support

> **2026 reconciliation (first-party verified):** most limitations previously listed here are stale. Gemini CLI now natively supports hooks (via `.gemini/settings.json`, e.g. `SessionEnd`), sub-agent dispatch with custom named agents (`.gemini/agents/*.md`), per-task model routing, and custom commands (`.gemini/commands/*.toml`) — see `docs/COMPATIBILITY-MATRIX.md` / ADR-031.

Still true:

- Per-pattern rule scoping (everything is always-loaded — no per-file routing).
- No built-in memory directory — DIY at `.memory/`.
- No native scheduler.
- CONDUCTOR emits eight native role profiles, including Tier 3 utility. Hook emission remains limited to the verified self-improvement Reflector lifecycle hook; unsupported Claude hook contracts are not copied.

## Difficulty translation

Every role carries its unchanged CONDUCTOR Tier and emits the project-saved model.
Initial setup recommends Gemini's semantic `pro`, `flash`, and `flash-lite` aliases.
Exact choices are maintained with `omniconductor models configure --target=gemini`;
inherited environment variables cannot replace the saved mapping.

## Strengths to lean into

- Large context — loading the entire bundled `GEMINI.md` is cheap on Gemini Pro models.
- Use Gemini for "read everything, then answer" workflows where bundled rules are an asset, not a cost.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Gemini adapter emits the Reflector loop (ADR-032):

- **Hook**: `.gemini/settings.json` — registers `.conductor/reflect/trajectory-log.sh` on the `SessionEnd` event. Written only if no settings/hook config exists; if one is already present, the adapter emits a manual-merge log entry instead of overwriting.
- **Command**: `.gemini/commands/reflect.toml` — the `/reflect` command that distills the trajectory log into lesson candidates.
- **Agent**: `.gemini/agents/reflector.md` — named reflector agent for the distillation pass.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification

`adapters/gemini/transform.sh` is **implemented**. The adapter emits, on a real
install, `GEMINI.md` (5 universal rules + compressed workflow + ABSOLUTE summary +
docs pointer + DIY `.memory/` note), the opt-in `.gemini/styleguide.md` (when
`--recipes=coding-conventions`), the `docs/*` templates, and a
`.conductor-manifest.json` (supports `--uninstall`). Flags: `--recipes=`,
`--dry-run`, `--no-prompt`, `--uninstall`/`--force`, `--help`.

The two runtime-citation checks below still require a live Gemini CLI session
(whether the model actually cites the loaded files), so they remain observed-only:

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| Adapter emits `GEMINI.md` + `.gemini/styleguide.md` + `docs/*` | ✅ implemented | `bash adapters/gemini/transform.sh <target> --no-prompt --recipes=coding-conventions` then inspect the tree. |
| `GEMINI.md` auto-loads on session start | ⏳ live session | Open project with Gemini CLI; verify it cites `GEMINI.md` content. |
| `.gemini/styleguide.md` auto-loads | ⏳ live session | Ask Gemini for code-style guidance; verify styleguide cited. |
