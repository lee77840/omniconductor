# COMPATIBILITY MATRIX — CONDUCTOR per tool

This matrix describes which CONDUCTOR features are supported by each target tool. ✅ = native support, ⚠️ = partial / requires manual work, ❌ = not supported.

> **Status note (re-verified 2026-07-04)**: ratings are the *tool-capability* level, re-verified against **first-party sources** (official docs / changelogs / tool GitHub repos) on 2026-07-04. The prior matrix (dated 2026-05-03) marked hooks and several other features as Claude-only; that is now **out of date** — all six tools ship event hooks (see the Hooks row + footnotes).
>
> **Capability ≠ CONDUCTOR emission.** A ✅ here means the *tool* documents the feature, NOT that a CONDUCTOR adapter already compiles to it. **Update (2026-07-04, ADR-032):** the **self-improvement / Reflector loop is now emitted for all six adapters** (a session-end trajectory-log hook, a `/reflect` command, a reflector agent-or-rule, and the prune script — recipe-gated on `--recipes=self-improvement`), so for that one capability the emission gap is closed on every tool (Windsurf via `post_cascade_response_with_transcript`, which is per-response not per-session). **Update (2026-07-05, ADR-033):** weekly-run scheduling is now shipped too — every adapter emits `.conductor/reflect/run-weekly.sh` (auto-detects the tool's headless CLI) + `SCHEDULING.md` (per-tool cron/launchd + native-scheduler registration, with the cloud-scheduler-can't-see-local-trajectories caveat). **Still Phase 2:** emitting the *rest* of the hook set (agent-routing / commit / large-file guards) on the five non-Claude adapters (see `docs/specs/2026-07-03-multitool-parity-reverification-SPEC-B-handoff.md`). Cells corrected in this pass are limited to what a first-party source confirms; unverifiable claims are hedged in the footnotes rather than shipped as ✅.
>
> **Naming:** Windsurf was **rebranded to "Devin Desktop"** (June 2026, per its own changelog); the "Windsurf" column name is kept here for adopter familiarity. Its **rules** now live under `.devin/rules/` (legacy `.windsurf/rules/`); other config (workflows, memories) remains under `.windsurf/` and `~/.codeium/windsurf/` — see footnote 11.

## Feature support matrix

| Feature | Claude Code | Cursor | Copilot | Gemini CLI | Codex | Windsurf |
|---|---|---|---|---|---|---|
| **Sub-agent dispatch** (Plan → delegate → verify) | ✅ Agent tool | ✅¹ | ✅¹ | ✅¹ | ✅¹ | ✅¹ |
| **Hooks** (PreToolUse / Stop / etc.) | ✅ | ✅² | ✅² | ✅² | ✅² | ⚠️² |
| **Custom named agents** (own system prompt) | ✅ `.claude/agents/*.md` | ✅³ | ✅³ | ✅³ | ✅³ | ⚠️³ |
| **Per-task model routing** (triage per call/agent) | ✅ per-call `model:` | ✅⁴ | ✅⁴ | ✅⁴ | ✅⁴ | ✅⁴ |
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

**Footnotes (first-party sources, verified 2026-07-04).** ✅ = tool capability confirmed; it does NOT mean a CONDUCTOR adapter emits it yet (non-Claude emission is Phase 2 — see the status note).

1. **Sub-agent dispatch** — Cursor 2.4+ (`cursor.com/docs/subagents`), Copilot VS Code (`code.visualstudio.com/docs/copilot/agents/subagents`), Gemini CLI (`enableAgents`, on by default), Codex (on by default, `max_depth` 1), Windsurf via **Devin Local**. All single-level nesting. CONDUCTOR keeps sub-agent *compilation* Claude-only by design (ADR-004); the ✅s mark native tool capability, a candidate to revisit — not current emission.
2. **Hooks** — Cursor v1.7 (2025-09-29 beta), Gemini v0.26.0 (2026-01-28, default-on), Copilot CLI + cloud-agent + VS Code (Preview; Claude-Code hook *format*, with different tool names), Codex (default-on; intro date not pinnable first-party). Windsurf ⚠️: 12 hook events but **no session-start/end**, so Stop-style enforcement is unavailable.
3. **Custom named agents** — Cursor `.cursor/agents/` (also reads `.claude/agents/`), Copilot `.github/agents/*.agent.md`, Gemini `.gemini/agents/*.md`, Codex `~/.codex/agents/*.toml` (`developer_instructions` + optional per-agent model). Windsurf ⚠️: documented for **Devin CLI** (`.devin/agents/{name}/AGENT.md`); Desktop confirmation implicit only.
4. **Per-task model routing** — corrects the old "single model per session" claim. Cursor per-chat + per-subagent `model:`; Copilot per-request + per-agent `model:`; Gemini `--model`/`/model`/per-subagent; Codex per-invocation `-m` / `/model` / per-profile; Windsurf per-conversation dropdown + per-subagent defaults.
5. **Slash / custom commands** — Cursor `.cursor/commands/*.md` (→ Skills in 2.4+), Copilot prompt files `.github/prompts/*.prompt.md`, Gemini `.gemini/commands/*.toml`, Codex Skills `.agents/skills` (`~/.codex/prompts/*.md` still work but deprecated), Windsurf workflows `.windsurf/workflows/*.md` (manual-only).
6. **Built-in managed memory** — Copilot "Copilot Memory" (preview; on-by-default for Pro since 2026-03; 28-day expiry), Codex `~/.codex/memories/` (opt-in), Windsurf `~/.codeium/windsurf/memories/`. ⚠️ Cursor: Memories GA'd in 1.2 but the docs page now redirects to Rules — current 2.x/3.x status unverified. ⚠️ Gemini: managed memory exists (hierarchical `GEMINI.md` + experimental Auto Memory) but the old `save_memory`/`/memory add` mechanism is gone from current docs.
7. **Native scheduled jobs** — Claude Routines, Cursor Automations (cloud-only, 2026-03), Copilot cloud-agent automations (2026-06-02) + CLI prompt scheduling, Codex Automations (cron; intro date not first-party). ⚠️ Gemini: no built-in scheduler — first-party path is the official GitHub Action on `schedule:`. ⚠️ Windsurf / Devin Desktop: no native desktop scheduler documented — external cron/launchd + Devin CLI is the only path.
8. **Transcripts** — Claude JSONL `~/.claude/projects/`, Cursor hook `transcript_path` (local on-disk path is unofficial → omitted), Gemini `~/.gemini/tmp/<hash>/chats/`, Codex `~/.codex/sessions/`, Windsurf transcript hook `~/.windsurf/transcripts/`. ⚠️ Copilot: hook `transcriptPath` only; the coding agent has **no transcript API** (UI / VS Code-viewable only).
9. **AGENTS.md** — Cursor/Copilot/Codex/Windsurf read it natively. ⚠️ Gemini: only via `context.fileName` config (default is `GEMINI.md`). Claude ⚠️: uses `CLAUDE.md` natively (Copilot/Codex also read `CLAUDE.md`).
10. **Lazy rules** — Gemini/Codex offer nested `GEMINI.md`/`AGENTS.md` directory-hierarchy scoping, not glob-on-file-touch loading.
11. **Windsurf paths** — rules are now `.devin/rules/` (legacy `.windsurf/rules/`). The CONDUCTOR Windsurf adapter **emits `.devin/rules/*.md`** (preferred) plus the always-loaded `.windsurfrules` baseline — target path already updated (as of v0.6).
12. **Auto-block enforcement** — every non-Claude tool now has hooks that can block (exit-code-2 / deny), so spec-as-you-go and review enforcement are *capable* on Cursor/Copilot/Gemini/Codex. ⚠️ Windsurf: no Stop/session event → pre-tool blocking only. CONDUCTOR emits these hooks for Claude only today; non-Claude hook emission is Phase 2. Copilot review = native GitHub PR review (a different mechanism).

## Tier assignment

Tiers are re-defined for the 2026 reality. The old T3 definition ("sub-agents/hooks not available") is obsolete — every tool now has hooks + sub-agents + custom agents + per-task model routing + commands. Tiers now reflect **how completely CONDUCTOR can map the full workflow** (glob rule-scoping, Stop-style enforcement events, a native scheduler for the Reflector), and adapter-emission readiness.

| Tier | Tools | Definition |
|---|---|---|
| **T1 — Full** | Claude Code, Cursor | Glob rule-scoping + hooks (incl. session/stop events) + sub-agents + per-task model + native scheduler (Cursor's is cloud-only) all present. Claude emits all of it today; Cursor is the richest non-Claude target for Phase 2 emission. |
| **T2 — Good** | Copilot, Codex, Gemini CLI | Hooks + sub-agents + custom agents + per-task model + commands all present. Caveats: Copilot rule-scoping is glob (`applyTo:`) but the coding agent has no transcript API; Codex/Gemini scope by nested-file hierarchy, not glob; Gemini has no native scheduler (external Action). |
| **T3 — Basic** | Windsurf / Devin Desktop | Has hooks (but **no session/stop events** → no Stop-style enforcement), sub-agents (Devin Local), commands, memory. No desktop scheduler; rules path moved to `.devin/rules/` (adapter emits it). |

## Adapter outputs at a glance (generated)

<!-- generated:adapter-outputs-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Tool | Tier | Emitted outputs | Legacy paths (still read) | Live-verified | Headless CLI |
|---|---|---|---|---|---|
| Claude Code | T1 | `CLAUDE.md` + `.claude/rules` + `.claude/agents` + `.claude/hooks` + `.claude/settings.json` + `docs/CURRENT_WORK.md` | — | ✅ 2026-07-09 | `claude -p` |
| Cursor | T1 | `.cursor/rules` + `docs/CURRENT_WORK.md` | `.cursorrules` (legacy) | 🧪 pending | `cursor-agent -p` |
| Copilot | T2 | `.github/copilot-instructions.md` + `.github/instructions` + `docs/CURRENT_WORK.md` | — | 🧪 pending | `copilot -p` |
| Gemini CLI | T2 | `GEMINI.md` + `.gemini/styleguide.md` + `docs/CURRENT_WORK.md` | — | 🧪 pending | `gemini -p` |
| Codex | T2 | `AGENTS.md` + `docs/CURRENT_WORK.md` | `.codex/codex.md` (legacy) | ✅ 2026-07-09 | `codex exec` |
| Windsurf | T3 | `.windsurfrules` + `.devin/rules` + `docs/CURRENT_WORK.md` | `.windsurf/rules` (legacy) | 🧪 pending | `devin -p` |
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

CONDUCTOR's job is to make sure **whichever tool you pick, you get the same Plan → Architecture → Tasks → Implementation → Review → Spec workflow** — even if the enforcement mechanism degrades from "auto-blocked by hook" (Claude) to "rule reminder text" (everywhere else).

## What you LOSE going from Claude → other tools

This list used to be long. As of the 2026-07-04 re-verification it is **much shorter** — sub-agents, hooks, custom named agents, per-task model routing, and commands are now native across the ecosystem. Two real gaps remain:

- **CONDUCTOR adapter emission** — the framework's non-Claude adapters do not *yet* compile to those native hooks / agents / scheduled jobs. Until Phase 2 lands (see the Spec B handoff), the enforcement on Cursor/Copilot/Gemini/Codex/Windsurf is still rule-reminder text even though the *tool* could enforce it. This is a CONDUCTOR gap, not a tool gap.
- **Windsurf / Devin Desktop** — genuinely lacks session-start/stop hook events, so Stop-style "auto-block on missing spec update" cannot be built there regardless of adapter work; and it has no desktop scheduler for a Reflector job.

Smaller residuals: Gemini/Codex scope rules by nested-file hierarchy rather than glob-on-file-touch; Gemini has no built-in scheduler (use the official GitHub Action); Copilot's coding agent exposes no transcript API.

What you KEEP everywhere (unchanged):

- All rule text (operations, coding-conventions, token-economy, spec-as-you-go, model-routing).
- All doc templates (CURRENT_WORK, REMAINING_TASKS, PLANS, TASKS, INDEX, specs/_example).
- The 4-type memory pattern (built-in managed memory now also exists on Copilot/Codex/Windsurf).
- The Plan → Architecture → Tasks → Impl → Review → Spec phase definitions.

The discipline is portable. The *enforcement* is now portable in principle too — CONDUCTOR just has to emit it (Phase 2).

## Verification status

| Adapter | Adapter spec written | Transform script written | Format validator | Per-IDE smoke (manual) | Real install verified | Quirks documented |
|---|---|---|---|---|---|---|
| Claude Code | ✅ (P0) | ✅ (SHIPPED v0.2 P1) | ✅ `validate-adapter-output.sh claude` PASS (2026-05-10) | n/a (Claude Code CLI itself is the runtime; covered by orchestrator harness) | ✅ (7 uninstall verification cases 2026-05-10, ADR-020) | ✅ (ADR-019, ADR-020, IDE-COMPATIBILITY-NOTES § Claude) |
| Cursor | ✅ (P0) | ✅ (SHIPPED v0.2, ADR-021) | ✅ `validate-adapter-output.sh cursor` PASS (2026-05-10) | ⏳ pending (Cursor smoke — see IDE-SMOKE-TESTING § 1) | ⚠️ Synthetic-target smoke + format-validator PASS (4 cases 2026-05-10); real-IDE empirical verification deferred to adopter feedback | ✅ (ADR-021, IDE-COMPATIBILITY-NOTES § Cursor) |
| Copilot | ✅ (P0) | ✅ (SHIPPED v0.2, ADR-022) | ✅ `validate-adapter-output.sh copilot` PASS (2026-05-10) | ⏳ pending per IDE: VS Code (§ 2), Cursor+Copilot (§ 3), Windsurf (§ 4), JetBrains (§ 5), Neovim (§ 6) | ⚠️ Synthetic-target smoke + format-validator PASS (3 cases 2026-05-10 — fresh / adopter / per-rule); per-IDE real smoke deferred to adopter feedback | ✅ (ADR-022, IDE-COMPATIBILITY-NOTES § Copilot) |
| Gemini CLI | ✅ (P0) | ✅ (SHIPPED v0.2 — `adapters/gemini/transform.sh` → `GEMINI.md` + `.gemini/styleguide.md`) | ✅ `validate-adapter-output.sh gemini` PASS | n/a (CLI runtime) | ⚠️ Emit-verified (format-validator + synthetic-target smoke PASS); live runtime consumption by Gemini CLI still pending — see `docs/ADAPTER-LIVE-VERIFICATION.md` | ✅ (IDE-COMPATIBILITY-NOTES § Gemini) |
| Codex | ✅ (P0) | ✅ (SHIPPED v0.2 — `adapters/codex/transform.sh` → `AGENTS.md`) | ✅ `validate-adapter-output.sh codex` PASS | n/a (CLI runtime) | ✅ **Live-verified** — auto-probed by `tools/live-verify.sh` (`codex exec` loaded `AGENTS.md` and listed the universal rules + read-CURRENT_WORK-first); current date/CLI in the generated "Adapter outputs at a glance" table above. Also emit-verified (format-validator PASS). | ✅ (IDE-COMPATIBILITY-NOTES § Codex) |
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
