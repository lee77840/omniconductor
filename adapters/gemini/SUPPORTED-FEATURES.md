# Gemini CLI — supported features

Detailed matrix of which CONDUCTOR features Gemini CLI supports.

## Feature support

| Feature | Gemini support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `GEMINI.md` at project root | Auto-loaded by Gemini CLI on session start. |
| **Style guide convention** | ✅ Native | `.gemini/styleguide.md` | Coding-style-specific guide; complements GEMINI.md. |
| **Large-context capability** | ✅ Strength | Up to ~1M-2M tokens depending on Gemini Pro version | Bundled rule loading is no problem. |
| **Per-pattern rule scoping** | ❌ | — | All rules always-loaded. No per-file routing. |
| **Sub-agent dispatch** | ❌ | — | Single chat per task. |
| **Hooks** | ❌ | — | No commit-blocking. |
| **Per-call model routing** | ❌ | — | Single model per session. |
| **Custom slash commands** | ❌ | — | |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Gemini reads on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text in `GEMINI.md` reminds user | Self-policed. |
| **Two-stage code review enforcement** | ❌ rule reminder only | | |

## Universal-rule → Gemini bundle translation

For each `core/universal-rules/<rule>.md`:

1. Strip front-matter (Gemini doesn't use it).
2. Concatenate body content into `GEMINI.md` as a section with heading `## <rule name>`.
3. Tool-specific callouts:
   - `> **Gemini-only mechanism**` callouts (rare): keep.
   - `> **Claude-only mechanism**` callouts: REPLACE with `> **Note (Gemini)**: enforced by hook on Claude Code; on Gemini CLI, follow self-policed.`
   - Other tool callouts: STRIP.

## `.gemini/styleguide.md` content

Specifically the coding-conventions rule's body, formatted as a Gemini styleguide. Use Google's published styleguide format as inspiration if Gemini documents one.

## What Gemini DOES NOT support

- Per-pattern rule scoping (everything is always-loaded).
- Sub-agent dispatch (per ADR-004 — not faked).
- Hooks.
- Per-call model routing.
- Custom slash commands.
- Built-in memory directory.

## Strengths to lean into

- Large context — loading the entire bundled `GEMINI.md` is cheap on Gemini Pro models.
- Use Gemini for "read everything, then answer" workflows where bundled rules are an asset, not a cost.

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
