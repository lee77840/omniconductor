# COMPATIBILITY MATRIX — CONDUCTOR per tool

This matrix describes which CONDUCTOR features are supported by each target tool. ✅ = native support, ⚠️ = partial / requires manual work, ❌ = not supported.

> **Status note (re-verified 2026-07-04)**: ratings are the *tool-capability* level, re-verified against **first-party sources** (official docs / changelogs / tool GitHub repos) on 2026-07-04. The prior matrix (dated 2026-05-03) marked hooks and several other features as Claude-only; that is now **out of date** — all six tools ship event hooks (see the Hooks row + footnotes).
>
> **Capability ≠ CONDUCTOR emission.** A ✅ in the feature matrix means the tool documents the capability. **Runtime update (2026-07-13, ADR-045/049):** full/strict installs emit eight role entries—including Tier 3 utility—for every adapter, and the CLI performs one-time saved Tier-model setup before role emission. Claude, Cursor, Copilot, Gemini, and Codex receive native model fields; Windsurf receives an explicit Adaptive session preflight because its workflow schema has no model field. Claude keeps the full guard set. Codex receives a verified native `PreToolUse`/`Stop` subset. Other adapters emit only lifecycle hooks whose native contracts are verified.
>
> **Naming:** Windsurf was **rebranded to "Devin Desktop"** (June 2026, per its own changelog); the "Windsurf" column name is kept here for adopter familiarity. Its **rules** now live under `.devin/rules/` (legacy `.windsurf/rules/`); other config (workflows, memories) remains under `.windsurf/` and `~/.codeium/windsurf/` — see footnote 11.

## Feature support matrix

| Feature | Claude Code | Cursor | Copilot | Gemini CLI | Codex | Windsurf |
|---|---|---|---|---|---|---|
| **Sub-agent dispatch** (Plan → delegate → verify) | ✅ Agent tool | ✅¹ | ✅¹ | ✅¹ | ✅¹ | ✅¹ |
| **Hooks** (PreToolUse / Stop / etc.) | ✅ | ✅² | ✅² | ✅² | ✅² | ⚠️² |
| **Custom named agents** (own system prompt) | ✅ `.claude/agents/*.md` | ✅³ | ✅³ | ✅³ | ✅³ | ⚠️³ |
| **Difficulty/model translation** | ✅ saved alias / exact ID | ✅ saved exact ID; provider fallback possible | ✅ saved exact ID; policy-controlled | ✅ saved semantic alias / exact ID | ✅ saved model + reasoning effort | ⚠️ saved Adaptive; advisory-session |
| **Slash / custom commands** | ✅ | ✅⁵ | ✅⁵ | ✅⁵ | ✅⁵ | ✅⁵ |
| **Built-in managed memory** | ✅ `~/.claude/projects/.../memory/` | ⚠️⁶ | ✅⁶ | ⚠️⁶ | ✅⁶ | ✅⁶ |
| **Native scheduled agents/jobs** | ✅ Routines | ✅⁷ | ✅⁷ | ⚠️⁷ | ✅⁷ | ⚠️⁷ |
| **Machine-readable transcripts** | ✅ JSONL | ✅⁸ | ⚠️⁸ | ✅⁸ | ✅⁸ | ✅⁸ |
| **AGENTS.md context file** | ⚠️⁹ (CLAUDE.md) | ✅⁹ | ✅⁹ | ⚠️⁹ | ✅⁹ | ✅⁹ |
| **Lazy-loaded rules** (glob on file-touch) | ✅ paths front-matter | ✅ `globs:` on `.mdc` | ✅ `applyTo:` | ⚠️¹⁰ | ⚠️¹⁰ | ⚠️ directory-based |
| **Always-loaded baseline** | ✅ `CLAUDE.md` | ✅ `.cursor/rules/*.mdc` (`alwaysApply`; `.cursorrules` legacy) | ✅ `applyTo: '**'` | ✅ `GEMINI.md` | ✅ `AGENTS.md` | ✅ `.windsurf`/`.devin` rules¹¹ |
| **Skill / plugin ecosystem** | ✅ | ✅ Skills⁵ | ⚠️ MCP + prompt files | ⚠️ tools + extensions | ✅ Skills⁵ | ⚠️ workflows/skills |
| **Spec-as-you-go enforcement (auto-block)** | ✅ Stop hook | ✅¹² | ✅¹² | ✅¹² | ✅¹² | ⚠️¹² |
| **Two-stage code review enforcement** | ✅ Stop hook | ✅¹² | ✅¹² (+ native PR review) | ✅¹² | ✅¹² | ⚠️¹² |
| **In-repo doc templates work as-is** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Bilingual rule support (한/영)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Footnotes (first-party sources, verified 2026-07-04; emission updated 2026-07-13).** ✅ = tool capability confirmed; see the status note for what CONDUCTOR emits.

1. **Sub-agent dispatch** — Cursor 2.4+ (`cursor.com/docs/subagents`), Copilot VS Code (`code.visualstudio.com/docs/copilot/agents/subagents`), Gemini CLI (`enableAgents`, on by default), and Codex support project role profiles. CONDUCTOR emits those native profiles. Windsurf gets role workflows because Desktop custom-agent profile discovery is not claimed without a verified contract.
2. **Hooks** — Cursor v1.7 (2025-09-29 beta), Gemini v0.26.0 (2026-01-28, default-on), Copilot CLI + cloud-agent + VS Code (Preview; Claude-Code hook *format*, with different tool names), Codex (default-on; intro date not pinnable first-party). Windsurf ⚠️: 12 hook events but **no session-start/end**, so Stop-style enforcement is unavailable.
3. **Custom named agents** — Cursor `.cursor/agents/` (also reads `.claude/agents/`), Copilot `.github/agents/*.agent.md`, Gemini `.gemini/agents/*.md`, Codex `~/.codex/agents/*.toml` (`developer_instructions` + optional per-agent model). Windsurf ⚠️: documented for **Devin CLI** (`.devin/agents/{name}/AGENT.md`); Desktop confirmation implicit only.
4. **Difficulty/model translation** — CONDUCTOR does not equate provider SKUs. One-time setup saves each adapter's Tier mapping. Claude and Gemini recommendations use aliases; Codex uses saved models plus effort; Cursor/Copilot use saved exact native fields while provider availability/policy stays authoritative. Windsurf is explicitly advisory-session because workflows cannot pin or inspect the Cascade selector (ADR-048/049).
5. **Slash / custom commands** — Cursor `.cursor/commands/*.md` (→ Skills in 2.4+), Copilot prompt files `.github/prompts/*.prompt.md`, Gemini `.gemini/commands/*.toml`, Codex Skills `.agents/skills` (`~/.codex/prompts/*.md` still work but deprecated), Windsurf workflows `.windsurf/workflows/*.md` (manual-only).
6. **Built-in managed memory** — Copilot "Copilot Memory" (preview; on-by-default for Pro since 2026-03; 28-day expiry), Codex `~/.codex/memories/` (opt-in), Windsurf `~/.codeium/windsurf/memories/`. ⚠️ Cursor: Memories GA'd in 1.2 but the docs page now redirects to Rules — current 2.x/3.x status unverified. ⚠️ Gemini: managed memory exists (hierarchical `GEMINI.md` + experimental Auto Memory) but the old `save_memory`/`/memory add` mechanism is gone from current docs.
7. **Native scheduled jobs** — Claude Routines, Cursor Automations (cloud-only, 2026-03), Copilot cloud-agent automations (2026-06-02) + CLI prompt scheduling, Codex Automations (cron; intro date not first-party). ⚠️ Gemini: no built-in scheduler — first-party path is the official GitHub Action on `schedule:`. ⚠️ Windsurf / Devin Desktop: no native desktop scheduler documented — external cron/launchd + Devin CLI is the only path.
8. **Transcripts** — Claude JSONL `~/.claude/projects/`, Cursor hook `transcript_path` (local on-disk path is unofficial → omitted), Gemini `~/.gemini/tmp/<hash>/chats/`, Codex `~/.codex/sessions/`, Windsurf transcript hook `~/.windsurf/transcripts/`. ⚠️ Copilot: hook `transcriptPath` only; the coding agent has **no transcript API** (UI / VS Code-viewable only).
9. **AGENTS.md** — Cursor/Copilot/Codex/Windsurf read it natively. ⚠️ Gemini: only via `context.fileName` config (default is `GEMINI.md`). Claude ⚠️: uses `CLAUDE.md` natively (Copilot/Codex also read `CLAUDE.md`).
10. **Lazy rules** — Gemini/Codex offer nested `GEMINI.md`/`AGENTS.md` directory-hierarchy scoping, not glob-on-file-touch loading.
11. **Windsurf paths** — rules are now `.devin/rules/` (legacy `.windsurf/rules/`). The CONDUCTOR Windsurf adapter **emits `.devin/rules/*.md`** (preferred) plus the always-loaded `.windsurfrules` baseline — target path already updated (as of v0.6).
12. **Auto-block enforcement** — tool capability varies. CONDUCTOR emits the full set for Claude and verified commit/session/review guards for Codex. Cursor/Copilot/Gemini retain rule obligations plus their verified Reflector hook; Windsurf uses the per-response Reflector hook and external Git/CI gates.

## Tier assignment

Compatibility tiers reflect **how completely CONDUCTOR can map the full workflow** (rule scoping, verified lifecycle events, native role surface, and scheduler). They are unrelated to the task difficulty Tier 1/2/3 contract in `meta-discipline.md`.

| Tier | Tools | Definition |
|---|---|---|
| **T1 — Full** | Claude Code, Cursor | Rich rule scoping plus native role surfaces. Claude emits the full guard set; Cursor emits roles while unverified guard translations remain excluded. |
| **T2 — Good** | Copilot, Codex, Gemini CLI | Native role/config surfaces and commands are present. Caveats: Copilot rule-scoping is glob (`applyTo:`) but the coding agent has no transcript API; Codex/Gemini scope by nested-file hierarchy, not glob; Gemini has no native scheduler (external Action). |
| **T3 — Basic** | Windsurf / Devin Desktop | Has hooks (but **no session/stop events** → no Stop-style enforcement), sub-agents (Devin Local), commands, memory. No desktop scheduler; rules path moved to `.devin/rules/` (adapter emits it). |

## Adapter outputs at a glance (generated)

<!-- generated:adapter-outputs-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Tool | Tier | Emitted outputs | Legacy paths (still read) | Live-verified | Headless CLI | À la carte (`--mode`) |
|---|---|---|---|---|---|---|
| Claude Code | T1 | `CLAUDE.md` + `.claude/rules` + `.claude/agents` + `.claude/hooks` + `.claude/settings.json` + `docs/CURRENT_WORK.md` | — | ✅ 2026-07-09 | `claude -p` | per-file |
| Cursor | T1 | `.cursor/rules` + `.cursor/agents` + `docs/CURRENT_WORK.md` | `.cursorrules` (legacy) | 🧪 pending | `cursor-agent -p` | per-file |
| Copilot | T2 | `.github/copilot-instructions.md` + `.github/instructions` + `.github/agents` + `docs/CURRENT_WORK.md` | — | 🧪 pending | `copilot -p` | per-file |
| Gemini CLI | T2 | `GEMINI.md` + `.gemini/styleguide.md` + `.gemini/agents` + `docs/CURRENT_WORK.md` | — | 🧪 pending | `gemini -p` | marked block |
| Codex | T2 | `AGENTS.md` + `.codex/conductor/rules` + `.codex/agents` + `.codex/hooks` + `.codex/hooks.json` + `docs/CURRENT_WORK.md` | `.codex/codex.md` (legacy) | ✅ 2026-07-13 | `codex exec` | marked block |
| Windsurf | T3 | `.windsurfrules` + `.devin/rules` + `.windsurf/workflows` + `docs/CURRENT_WORK.md` | `.windsurf/rules` (legacy) | 🧪 pending | `devin -p` | per-file |
<!-- /generated:adapter-outputs-table -->

Source of truth: `adapters/<tool>/metadata.json` (ADR-040) — CI regenerates and fails on drift.

## Verdict — "If you need X, use Y"

| Need | Recommended tool |
|---|---|
| Multi-file refactor with delegated sub-agents + auto-blocking on missing spec updates | **Claude Code** |
| Fast in-IDE chat + completion + decent rule scoping | **Cursor** |
| In-line completion + PR review automation tied to GitHub | **GitHub Copilot** |
| Cheap large-context exploration over long files | **Gemini CLI** |
| Shell-driven scripting tasks | **Codex** |
| Cursor-like flow in a different IDE | **Windsurf** |

CONDUCTOR's job is to make sure **whichever tool you pick, you get the same Plan → Architecture → Tasks → Implementation → Review → Spec workflow**, while describing mechanical enforcement at its actual per-tool strength.

## What you LOSE going from Claude → other tools

This list used to be long. Current adapters now provide a verified native role or workflow entry point for all six tools. Two real gaps remain:

- **Guard parity** — native role emission is now closed across all adapters (Windsurf via workflows). Guard parity is intentionally partial: Codex gets verified native guards; the other non-Claude adapters do not receive unverified translations of Claude hook contracts.
- **Windsurf / Devin Desktop** — genuinely lacks session-start/stop hook events, so Stop-style "auto-block on missing spec update" cannot be built there regardless of adapter work; and it has no desktop scheduler for a Reflector job.

Smaller residuals: Gemini/Codex scope rules by nested-file hierarchy rather than glob-on-file-touch; Gemini has no built-in scheduler (use the official GitHub Action); Copilot's coding agent exposes no transcript API.

What you KEEP everywhere (unchanged):

- All rule text, including the vendor-neutral difficulty routing contract.
- All doc templates (CURRENT_WORK, REMAINING_TASKS, PLANS, TASKS, INDEX, specs/_example).
- The 4-type memory pattern (built-in managed memory now also exists on Copilot/Codex/Windsurf).
- The Plan → Architecture → Tasks → Impl → Review → Spec phase definitions.

The discipline and role topology are portable. Mechanical enforcement is explicit and capability-specific.

## Verification status

| Adapter | Adapter spec written | Transform script written | Format validator | Per-IDE smoke (manual) | Real install verified | Quirks documented |
|---|---|---|---|---|---|---|
| Claude Code | ✅ (P0) | ✅ (SHIPPED v0.2 P1) | ✅ `validate-adapter-output.sh claude` PASS (2026-05-10) | n/a (Claude Code CLI itself is the runtime; covered by orchestrator harness) | ✅ (7 uninstall verification cases 2026-05-10, ADR-020) | ✅ (ADR-019, ADR-020, IDE-COMPATIBILITY-NOTES § Claude) |
| Cursor | ✅ (P0) | ✅ (SHIPPED v0.2, ADR-021) | ✅ `validate-adapter-output.sh cursor` PASS (2026-05-10) | ⏳ pending (Cursor smoke — see IDE-SMOKE-TESTING § 1) | ⚠️ Synthetic-target smoke + format-validator PASS (4 cases 2026-05-10); real-IDE empirical verification deferred to adopter feedback | ✅ (ADR-021, IDE-COMPATIBILITY-NOTES § Cursor) |
| Copilot | ✅ (P0) | ✅ (SHIPPED v0.2, ADR-022) | ✅ `validate-adapter-output.sh copilot` PASS (2026-05-10) | ⏳ pending per IDE: VS Code (§ 2), Cursor+Copilot (§ 3), Windsurf (§ 4), JetBrains (§ 5), Neovim (§ 6) | ⚠️ Synthetic-target smoke + format-validator PASS (3 cases 2026-05-10 — fresh / adopter / per-rule); per-IDE real smoke deferred to adopter feedback | ✅ (ADR-022, IDE-COMPATIBILITY-NOTES § Copilot) |
| Gemini CLI | ✅ (P0) | ✅ (SHIPPED v0.2 — `adapters/gemini/transform.sh` → `GEMINI.md` + `.gemini/styleguide.md`) | ✅ `validate-adapter-output.sh gemini` PASS | n/a (CLI runtime) | ⚠️ Emit-verified (format-validator + synthetic-target smoke PASS); live runtime consumption by Gemini CLI still pending — see `docs/ADAPTER-LIVE-VERIFICATION.md` | ✅ (IDE-COMPATIBILITY-NOTES § Gemini) |
| Codex | ✅ (P0) | ✅ bounded `AGENTS.md` kernel + full `.codex/conductor/` references | ✅ validator enforces kernel/reference completeness and byte budget | n/a (CLI runtime) | ✅ **Native-input verified** — `codex debug prompt-input` confirmed the kernel end marker is model-visible without an external model call; current date/CLI in the generated table above. | ✅ (IDE-COMPATIBILITY-NOTES § Codex) |
| Windsurf | ✅ (P0) | ✅ (SHIPPED v0.2 — own `adapters/windsurf/transform.sh` → `.windsurfrules` + `.devin/rules/*.md` (legacy `.windsurf/rules/` still read) — see footnote 11) | ✅ `validate-adapter-output.sh windsurf` PASS | ⏳ adopter follow-up / live-pending (IDE-SMOKE-TESTING § 4) | ⚠️ Emit-verified (format-validator + synthetic-target smoke PASS); live runtime consumption still pending — see `docs/ADAPTER-LIVE-VERIFICATION.md` | ✅ (IDE-COMPATIBILITY-NOTES § Windsurf) |

## Copilot adapter — IDE coverage

The Copilot adapter is the strategic ROI win in P3: a single transform.sh produces files (`.github/copilot-instructions.md` + `.github/instructions/*.instructions.md`) that every IDE with a Copilot client reads natively. Adopters do not run the adapter once per IDE.

| IDE | Copilot client | Reads `.github/copilot-instructions.md` | Reads `.github/instructions/*.instructions.md` | Empirical verification | Smoke checklist |
|---|---|---|---|---|---|
| VS Code | Built-in (Copilot extension) | ✅ documented | ✅ documented | ⏳ adopter follow-up | `IDE-SMOKE-TESTING.md` § 2 |
| Cursor | Copilot extension (in addition to native `.cursor/rules/`) | ✅ documented | ⚠️ depends on extension version | ⏳ adopter follow-up | `IDE-SMOKE-TESTING.md` § 3 |
| Windsurf | Copilot adapter | ✅ documented | ⚠️ depends on adapter version | ⏳ adopter follow-up | `IDE-SMOKE-TESTING.md` § 4 |
| JetBrains family (IntelliJ, WebStorm, PyCharm, etc.) | Copilot plugin | ✅ documented | ✅ documented (2024.3+) | ⏳ adopter follow-up | `IDE-SMOKE-TESTING.md` § 5 |
| Neovim | `copilot.vim` (or `copilot.lua`) | ⚠️ chat-only feature; completion side ignores | ⚠️ chat-only feature | ⏳ adopter follow-up | `IDE-SMOKE-TESTING.md` § 6 |

The "documented" column reflects GitHub's official Copilot custom-instructions spec. Per-IDE empirical verification (open the IDE, confirm the rule shows in Copilot Chat references, edit a matching file, verify the per-file instruction loads) is now covered by the manual smoke checklists in `IDE-SMOKE-TESTING.md` (one section per IDE) — adopter-driven, results recorded back into the "Per-IDE smoke (manual)" column above. `transform.sh` is auto-validated by `tools/validate-adapter-output.sh` (format-level conformance) plus the original three temp-target install smoke runs against a synthetic Conductor source tree. Per-IDE quirks are inventoried in `docs/IDE-COMPATIBILITY-NOTES.md`.
