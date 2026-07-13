# IDE Compatibility Notes — known quirks per consumer

> Companion to `docs/IDE-SMOKE-TESTING.md`. This is the inventory of known IDE-specific quirks, edge cases, and capability gaps that affect how Conductor's adapter outputs (`.cursor/rules/*.mdc`, `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`) actually behave once an IDE picks them up.
>
> **Scope**: format-level differences and consumer-side limitations only. Adapter-side decisions (what Conductor produces) are documented in each adapter's `transform-spec.md`.
>
> **Maintenance**: when smoke testing surfaces a new quirk, append to the relevant section below. Date the entry. Do NOT delete entries — they're a record of platform drift.

---

## Cursor (`.cursor/rules/*.mdc`)

### Frontmatter parsing

- `description:` — single-line string. Multi-line via YAML `>` or `|` block scalar is **untested**; safe assumption: keep it ≤ 1 line.
- `globs:` — three accepted forms (Cursor late-2025):
  1. Block array: `globs:\n  - "**"\n  - "src/**"`
  2. Inline array: `globs: ["**", "src/**"]`
  3. Single string: `globs: "**"` (treated as 1-element array internally)
  Conductor's Cursor adapter emits inline-array form by default. Validator accepts all three.
- `alwaysApply:` — boolean. `true` / `false` (lowercase). Pre-late-2025 builds ignored this field; modern builds honor it.
- Unknown frontmatter fields: silently ignored (no warning surface in Cursor UI).

### Body / markdown handling

- Standard markdown rendering in Cursor's Rules panel. Code fences (` ``` `) render as code blocks.
- Cursor truncates rule bodies in the panel preview after ~500 chars. Full body still loaded into AI context.
- HTML embedded in markdown: rendered as plain text in panel (sanitized), but full text passed to AI.

### Loading mechanism

- Cursor reloads rules when the project is reopened OR when `Cmd/Ctrl+Shift+P` → `Developer: Reload Window` runs.
- File-watcher-based hot-reload: works for `.cursorrules` (legacy) but for `.cursor/rules/*.mdc` is **inconsistent** across Cursor builds. Smoke step 5 in `IDE-SMOKE-TESTING.md` instructs explicit reload.
- New chat sessions reload rules; existing chat sessions retain their initial rule snapshot. To test a rule edit, ALWAYS open a fresh chat.

### Known issues

- (2025-Q4) Some Cursor builds silently drop rules whose body exceeds ~50 KB. Mitigation: keep each `.mdc` under 30 KB. Conductor's universal-rules range 5-15 KB, well within limit.
- (2025-Q4) `globs:` matching is performed by Cursor's internal matcher, NOT standard glob libraries. Confirmed-working patterns: `**`, `src/**`, `*.ts`, `**/*.tsx`. Unconfirmed: extended brace expansion `{a,b}`, negative globs `!`. Avoid these; if needed, fall back to multiple positive globs.

---

## GitHub Copilot — top-level `.github/copilot-instructions.md`

### Loading

- Loaded by Copilot Chat in any IDE with the Copilot Chat extension/plugin.
- NOT loaded by Copilot Completion (in-line ghost-text suggestions). Completion has its own narrower context channel.
- Loaded once per chat session at session start. Edits during a session are picked up on the next request (no explicit reload needed in most clients).

### Format

- Plain markdown. NO frontmatter required (and frontmatter, if added, is treated as part of the body).
- Body length: GitHub's docs as of 2025-Q4 don't publish a hard cap. Empirical reports suggest > 200 KB starts truncation in chat context. Conductor's bundle ranges 30-60 KB depending on recipes.
- Encoding: UTF-8 only.

### Known issues

- **Silent truncation**: Copilot Chat may silently drop the tail of an oversized instruction file with no UI signal. If you see only the early sections referenced in chat answers, suspect truncation; trim the file.
- **"Used N references" footer ambiguity**: the footer counts the file as ONE reference even if Copilot only loaded the first 10 KB. Don't rely on the footer to confirm full loading.

---

## GitHub Copilot — per-file `.github/instructions/*.instructions.md`

### `applyTo:` field

- Format: **CSV string in quotes**, e.g., `applyTo: 'src/**,docs/**'`.
- YAML arrays — block (`- "src/**"`) or inline (`["src/**"]`) — are **rejected silently**. Conductor validator catches this.
- Comma-separation only; no semicolons or pipes.
- Glob syntax: micromatch-compatible (per GitHub's docs late-2025). Brace expansion `{a,b}` works. Negation `!` works in some IDEs (VS Code reliably; JetBrains inconsistently).
- `applyTo: '**'` = applies to every file (equivalent to "always-loaded").

### Per-IDE consumer support

| IDE / Client | Reads `.github/copilot-instructions.md` (bundle) | Reads `.github/instructions/*.instructions.md` (per-file) | Notes |
|---|---|---|---|
| VS Code + Copilot Chat | Yes | Yes (post-2024-Q4 plugin) | Most reliable consumer. |
| Cursor + Copilot extension | Yes | Partial (depends on Copilot extension version) | Cursor's NATIVE `.cursor/rules/` takes priority in Cursor's own chat; Copilot's panel reads `.github/`. |
| Windsurf (Codeium) Cascade | Yes | Undocumented | Cascade reads top-level bundle reliably; per-file behavior is "best effort". |
| JetBrains + Copilot plugin | Yes (2024.1+) | Yes (2024.3+) | Older plugin builds: top-level only. |
| Neovim + `copilot.vim` (completion only) | No | No | Completion side ignores instructions entirely. |
| Neovim + `CopilotChat.nvim` | Yes (community plugin) | Partial | Tracks upstream Copilot Chat protocol with a lag. |
| GitHub.com PR review (Copilot for PRs) | Yes | Yes | Used at PR-review time; same instruction files apply. |

### Known issues

- **Copilot Completion ignores instructions almost universally**. Adopters expecting in-line completion to follow Conductor's rules will be disappointed. Document this expectation up-front.
- **CSV in `applyTo:` has no documented length limit** but GitHub's parser has been observed to truncate around 1024 characters in Copilot for VS Code. Keep glob lists short; prefer `**` over giant CSVs.
- **Multiple matching files compose additively** (per GitHub docs). Conductor leverages this — every per-file instruction with `applyTo: '**'` adds to the chat context. If you tighten globs, files outside the scope drop out.

---

## Claude Code — `.claude/rules/*.md`

### Frontmatter

- `paths:` — block array of glob strings. Required.
- `rule_id:`, `rule_name:` — optional metadata; not interpreted by Claude Code itself but visible to the orchestrator.
- Other fields ignored.

### Loading

- Auto-loaded when a tool call (Read / Edit / Write / Bash) touches a file matching one of the `paths:` globs.
- Always-loaded rules: use `paths: ["**"]`.
- Hot-reloadable: edits to a rule file take effect on the next tool call within the same session.

### Known issues

- (Internal Claude Code) `paths:` matching uses minimatch under the hood; brace expansion + negation supported.
- Rules with `paths: ["**"]` accumulate token cost on every tool call. Conductor's universal rules use `**` deliberately (always-loaded baseline); recipes scope to narrower globs.

---

## Cross-IDE format compatibility — adapter strategy

When the same Conductor source rule must compile to multiple targets:

| Source feature | Claude | Cursor | Copilot | Gemini | Codex | Windsurf |
|---|---|---|---|---|---|---|
| Always-loaded | `CLAUDE.md` / `paths: ["**"]` | `alwaysApply: true` | repo-wide instructions | `GEMINI.md` bundle | bounded `AGENTS.md` kernel | `.windsurfrules` |
| Path-scoped | `paths:` | `globs:` | `applyTo:` | bundle; no glob translation | routed `.codex/conductor/` reference | grouped `.devin/rules/` file |
| Native base roles | `.claude/agents/*.md` | `.cursor/agents/*.md` | `.github/agents/*.agent.md` | `.gemini/agents/*.md` | `.codex/agents/*.toml` | `.windsurf/workflows/*.md` |
| Tool-specific mechanisms | Preserve exact verified callout | Preserve exact verified callout | Preserve exact verified callout | Preserve exact verified callout | Preserve exact verified callout | Preserve exact verified callout |

The adapter `transform.sh` files implement these mappings. The format validator enforces that each adapter's output conforms to its target IDE's expectations.

---

## Format validator coverage

`tools/validate-adapter-output.sh` checks the format-level guarantees an IDE depends on:

| Check | Claude | Cursor | Copilot | Gemini | Codex | Windsurf |
|---|---|---|---|---|---|---|
| Rule/instruction structure | `paths:` rules | `.mdc` frontmatter | `applyTo:` string | bundle sections | bounded kernel + references | baseline + grouped rules |
| Eight native role entries | Yes | Yes | Yes | Yes | Yes | Yes (workflows) |
| Model-routing marker/control | Claude model field | saved model field | saved model field | saved family alias | model + effort | advisory preflight |
| Code fences / unresolved placeholders | Checked | Checked | Checked | Checked | Checked | Checked |

What the validator does NOT cover (intentional — these need a human in an IDE):

- Whether the IDE *actually loads* the rule (covered by `IDE-SMOKE-TESTING.md`).
- Whether the AI assistant *follows* the rule (non-deterministic — only patterns of behavior across many sessions can confirm).
- Whether glob patterns *match the intended files* in the adopter's repo (depends on adopter project structure).
- Whether the rule body's *content* is reasonable (subject-matter correctness — out of scope for a format validator).

---

## Reporting new quirks

If smoke testing surfaces a quirk not listed here:

1. Identify the IDE + version + plugin version.
2. Reproduce in a clean target (`/tmp/conductor-smoke-<ide>-<date>`).
3. Append a dated bullet under the relevant section above.
4. If the quirk warrants validator coverage, file an issue tagged `validator-gap`.
