# COMPATIBILITY MATRIX — CONDUCTOR per tool

This matrix describes which CONDUCTOR features are supported by each target tool. ✅ = native support, ⚠️ = partial / requires manual work, ❌ = not supported.

> **Status note (re-verified 2026-07-27)**: ratings are the *tool-capability* level, re-verified against **first-party sources** (official docs / changelogs / tool GitHub repos) through 2026-07-27. The prior matrix (dated 2026-05-03) marked hooks and several other features as Claude-only; that is now **out of date** — all six tools ship event hooks (see the Hooks row + footnotes).
>
> **Capability ≠ CONDUCTOR emission.** A ✅ in the feature matrix means the tool documents the capability. **Runtime update (2026-07-27, ADR-045/049/056):** full/strict installs emit eight role entries—including Tier 3 utility—for every adapter, and the CLI performs one-time saved Tier-model setup before role emission. Claude, Cursor, Copilot, Gemini, and Codex receive native model fields; Windsurf receives an explicit Adaptive session preflight because its workflow schema has no model field. Within P2's three portable policies, the hook compiler emits all three guards for Claude, Copilot, and Codex; review-before-stop for Cursor and Gemini; and rule fallbacks where a verified native decision contract is absent. This is not the total hook inventory: full Codex additionally emits its session-state Stop guard, and full Gemini additionally emits output-cap BeforeTool.
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
| **Portable Agent Skills** | ✅ `.claude/skills`¹⁴ | ✅ `.agents/skills`¹⁴ | ✅ `.agents/skills`¹⁴ | ✅ `.agents/skills`¹⁴ | ✅ `.agents/skills`¹⁴ | ✅ `.agents/skills`¹⁴ |
| **Spec-as-you-go enforcement (auto-block)** | ✅ Stop hook | ✅¹² | ✅¹² | ✅¹² | ✅¹² | ⚠️¹² |
| **Two-stage code review enforcement** | ✅ Stop hook | ✅¹² | ✅¹² (+ native PR review) | ✅¹² | ✅¹² | ⚠️¹² |
| **In-repo doc templates work as-is** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Bilingual rule support (한/영)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Tool-output cap (store-time)** | ✅ PostToolUse hook (≥v2.1.121)¹³ | ❌¹³ | ❌¹³ | ✅ BeforeTool shell rewrite (shell only)¹³ | ✅ native config key¹³ | ❌¹³ |

**Footnotes (first-party sources, verified 2026-07-04; emission updated 2026-07-13).** ✅ = tool capability confirmed; see the status note for what CONDUCTOR emits.

1. **Sub-agent dispatch** — Cursor 2.4+ (`cursor.com/docs/subagents`), Copilot VS Code (`code.visualstudio.com/docs/copilot/agents/subagents`), Gemini CLI (`enableAgents`, on by default), and Codex support project role profiles. CONDUCTOR emits those native profiles. Windsurf gets role workflows because Desktop custom-agent profile discovery is not claimed without a verified contract.
2. **Hooks** — Cursor v1.7 (2025-09-29 beta), Gemini v0.26.0 (2026-01-28, default-on), Copilot CLI + cloud-agent + VS Code (Preview; native camelCase events/payloads), Codex project hooks, and Claude nested hook groups are documented. Windsurf ⚠️: its post-response hook is asynchronous and cannot continue the just-finished turn, so Stop-style enforcement remains a rule fallback.
3. **Custom named agents** — Cursor `.cursor/agents/` (also reads `.claude/agents/`), Copilot `.github/agents/*.agent.md`, Gemini `.gemini/agents/*.md`, Codex `~/.codex/agents/*.toml` (`developer_instructions` + optional per-agent model). Windsurf ⚠️: documented for **Devin CLI** (`.devin/agents/{name}/AGENT.md`); Desktop confirmation implicit only.
4. **Difficulty/model translation** — CONDUCTOR does not equate provider SKUs. One-time setup saves each adapter's Tier mapping. Claude and Gemini recommendations use aliases; Codex uses saved models plus effort; Cursor/Copilot use saved exact native fields while provider availability/policy stays authoritative. Windsurf is explicitly advisory-session because workflows cannot pin or inspect the Cascade selector (ADR-048/049).
5. **Slash / custom commands** — Cursor `.cursor/commands/*.md` (→ Skills in 2.4+), Copilot prompt files `.github/prompts/*.prompt.md`, Gemini `.gemini/commands/*.toml`, Codex Skills `.agents/skills` (`~/.codex/prompts/*.md` still work but deprecated), Windsurf workflows `.windsurf/workflows/*.md` (manual-only).
6. **Built-in managed memory** — Copilot "Copilot Memory" (preview; on-by-default for Pro since 2026-03; 28-day expiry), Codex `~/.codex/memories/` (opt-in), Windsurf `~/.codeium/windsurf/memories/`. ⚠️ Cursor: Memories GA'd in 1.2 but the docs page now redirects to Rules — current 2.x/3.x status unverified. ⚠️ Gemini: managed memory exists (hierarchical `GEMINI.md` + experimental Auto Memory) but the old `save_memory`/`/memory add` mechanism is gone from current docs.
7. **Native scheduled jobs** — Claude Routines, Cursor Automations (cloud-only, 2026-03), Copilot cloud-agent automations (2026-06-02) + CLI prompt scheduling, Codex Automations (cron; intro date not first-party). ⚠️ Gemini: no built-in scheduler — first-party path is the official GitHub Action on `schedule:`. ⚠️ Windsurf / Devin Desktop: no native desktop scheduler documented — external cron/launchd + Devin CLI is the only path.
8. **Transcripts** — Claude JSONL `~/.claude/projects/`, Cursor hook `transcript_path` (local on-disk path is unofficial → omitted), Gemini `~/.gemini/tmp/<hash>/chats/`, Codex `~/.codex/sessions/`, Windsurf transcript hook `~/.windsurf/transcripts/`. ⚠️ Copilot: hook `transcriptPath` only; the coding agent has **no transcript API** (UI / VS Code-viewable only).
9. **AGENTS.md** — Cursor/Copilot/Codex/Windsurf read it natively. ⚠️ Gemini: only via `context.fileName` config (default is `GEMINI.md`). Claude ⚠️: uses `CLAUDE.md` natively (Copilot/Codex also read `CLAUDE.md`).
10. **Lazy rules** — Gemini/Codex offer nested `GEMINI.md`/`AGENTS.md` directory-hierarchy scoping, not glob-on-file-touch loading.
11. **Windsurf paths** — rules are now `.devin/rules/` (legacy `.windsurf/rules/`). The CONDUCTOR Windsurf adapter **emits `.devin/rules/*.md`** (preferred) plus the always-loaded `.windsurfrules` baseline — target path already updated (as of v0.6).
12. **Auto-block enforcement (ADR-056)** — P2's three portable policies are deliberately unequal only where provider contracts differ. Claude/Copilot/Codex emit the two commit soft-confirmations plus review continuation. Cursor/Gemini emit review continuation but keep the commit checks in rule text because their verified shell pre-hook decisions do not expose a soft `ask`. Windsurf keeps all three as rule fallbacks because its post-response hook cannot continue the turn. These counts exclude the existing Codex session-state Stop guard and Gemini output-cap BeforeTool hook. Existing user hook arrays are schema-merged, never replaced wholesale; only exact registry-rendered CONDUCTOR commands are refreshed.
13. **Tool-output cap (ADR-051/056)** — reach is honestly 3/6, not rounded up. Claude: `PostToolUse` hook returns `updatedToolOutput` (head+tail+marker); requires Claude Code ≥v2.1.121, below which it silently no-ops (`doctor` D5 warns). Codex: baked `tool_output_token_limit` in `.codex/config.toml` — its own tokenizer, not the shared hook. Gemini: `BeforeTool` rewrites `run_shell_command` only (not other tool types) to merge stdout+stderr and pipe the combined stream through a byte-capping `awk` truncator — head-only. Its registration is now schema-merged with arbitrary existing `.gemini/settings.json` keys and hook groups. Cursor/Copilot/Windsurf are ❌ N/A: none has a verified per-tool-call, store-time output-edit contract.
14. **Portable Agent Skills (ADR-055)** — full/minimal/strict installs emit the same instruction-only `plan-change`, `verify-change`, and `review-change` sources. Claude uses its native `.claude/skills`; Cursor, Copilot, Gemini, Codex, and Windsurf/Devin share byte-identical `.agents/skills`. Native activation differs by tool and is shown in the generated table below. This is emit-verified; model-backed discovery remains subject to each runtime, policy, and consent flow.

## Tier assignment

Compatibility tiers reflect **how completely CONDUCTOR can map the full workflow** (rule scoping, verified lifecycle events, native role surface, and scheduler). They are unrelated to the task difficulty Tier 1/2/3 contract in `meta-discipline.md`.

| Tier | Tools | Definition |
|---|---|---|
| **T1 — Full** | Claude Code, Cursor | Rich rule scoping plus native role surfaces. Claude emits the full guard set; Cursor emits its verified review-stop continuation and keeps unsupported soft confirmations as rule fallbacks. |
| **T2 — Good** | Copilot, Codex, Gemini CLI | Native role/config surfaces and commands are present. Caveats: Copilot rule-scoping is glob (`applyTo:`) but the coding agent has no transcript API; Codex/Gemini scope by nested-file hierarchy, not glob; Gemini has no native scheduler (external Action). |
| **T3 — Basic** | Windsurf / Devin Desktop | Has hooks (but **no session/stop events** → no Stop-style enforcement), sub-agents (Devin Local), commands, memory. No desktop scheduler; rules path moved to `.devin/rules/` (adapter emits it). |

## Adapter outputs at a glance (generated)

<!-- generated:adapter-outputs-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Tool | Tier | Emitted outputs | Legacy paths (still read) | Live-verified | Headless CLI | À la carte (`--mode`) |
|---|---|---|---|---|---|---|
| Claude Code | T1 | `CLAUDE.md` + `.claude/rules` + `.claude/agents` + `.claude/skills` + `.claude/hooks` + `.claude/settings.json` + `docs/CURRENT_WORK.md` | — | ✅ 2026-07-09 | `claude -p` | per-file |
| Cursor | T1 | `.cursor/rules` + `.cursor/agents` + `.cursor/hooks` + `.cursor/hooks.json` + `.agents/skills` + `docs/CURRENT_WORK.md` | `.cursorrules` (legacy) | 🧪 pending | `cursor-agent -p` | per-file |
| Copilot | T2 | `.github/copilot-instructions.md` + `.github/instructions` + `.github/agents` + `.github/hooks` + `.github/hooks/conductor-reflect.json` + `.agents/skills` + `docs/CURRENT_WORK.md` | — | 🧪 pending | `copilot -p` | per-file |
| Gemini CLI | T2 | `GEMINI.md` + `.gemini/styleguide.md` + `.gemini/agents` + `.gemini/hooks` + `.gemini/settings.json` + `.agents/skills` + `docs/CURRENT_WORK.md` | — | 🧪 pending | `gemini -p` | marked block |
| Codex | T2 | `AGENTS.md` + `.codex/conductor/rules` + `.codex/agents` + `.codex/hooks` + `.codex/hooks.json` + `.codex/config.toml` + `.agents/skills` + `docs/CURRENT_WORK.md` | `.codex/codex.md` (legacy) | ✅ 2026-07-13 | `codex exec` | marked block |
| Windsurf | T3 | `.windsurfrules` + `.devin/rules` + `.windsurf/workflows` + `.agents/skills` + `docs/CURRENT_WORK.md` | `.windsurf/rules` (legacy) | 🧪 pending | `devin -p` | per-file |
<!-- /generated:adapter-outputs-table -->

Source of truth: `adapters/<tool>/metadata.json` (ADR-040) — CI regenerates and fails on drift.

## Portable Agent Skills contract (generated)

<!-- generated:portable-skills-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Tool | Emitted project root | Path status | Activation | Example explicit invocation | First-party basis |
|---|---|---|---|---|---|
| Claude Code | `.claude/skills` | native | automatic + explicit | `/plan-change` | [official](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) (2026-07-27) |
| Cursor | `.agents/skills` | alias | automatic + explicit | `/plan-change` | [official](https://cursor.com/docs/skills) (2026-07-27) |
| Copilot | `.agents/skills` | documented-alternative | automatic + explicit | `/plan-change` | [official](https://docs.github.com/en/copilot/reference/customization-cheat-sheet) (2026-07-27) |
| Gemini CLI | `.agents/skills` | alias | automatic + activation consent | `not-documented` | [official](https://geminicli.com/docs/cli/using-agent-skills/) (2026-07-27) |
| Codex | `.agents/skills` | native | automatic + explicit | `$plan-change` | [official](https://developers.openai.com/codex/skills) (2026-07-27) |
| Windsurf | `.agents/skills` | recommended | automatic + explicit; one active | `@skills:plan-change` | [official](https://docs.devin.ai/product-guides/skills) (2026-07-27) |
<!-- /generated:portable-skills-table -->

The skills are procedures, not roles. They do not change the eight baseline roles,
optional Reflector, task-difficulty Tier 1/2/3 definitions, or saved model routing.

## Version-gated hook compiler contract (generated)

The compiler composes only CONDUCTOR-owned handlers into existing JSON and
preserves arbitrary adopter keys, events, and hook arrays. “Rule fallback”
means the same obligation remains in universal rule text because the provider
does not expose the required native decision or continuation contract.

<!-- generated:hook-compiler-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Tool | Schema-aware config | CURRENT_WORK commit check | Test-coverage commit check | Review-before-stop | First-party basis |
|---|---|---|---|---|---|
| Claude Code | `.claude/settings.json` | ✅ native | ✅ native | ✅ native | [official](https://code.claude.com/docs/en/hooks) (2026-07-27) |
| Cursor | `.cursor/hooks.json` | 📘 rule fallback | 📘 rule fallback | ✅ native | [official](https://cursor.com/blog/agent-best-practices) (2026-07-27) |
| Copilot | `.github/hooks/conductor-reflect.json` | ✅ native | ✅ native | ✅ native | [official](https://docs.github.com/en/copilot/reference/hooks-reference) (2026-07-27) |
| Gemini CLI | `.gemini/settings.json` | 📘 rule fallback | 📘 rule fallback | ✅ native | [official](https://geminicli.com/docs/hooks/reference/) (2026-07-27) |
| Codex | `.codex/hooks.json` | ✅ native | ✅ native | ✅ native | [official](https://learn.chatgpt.com/docs/hooks) (2026-07-27) |
| Windsurf | `.windsurf/hooks.json` | 📘 rule fallback | 📘 rule fallback | 📘 rule fallback | [official](https://docs.windsurf.com/windsurf/cascade/hooks) (2026-07-27) |
<!-- /generated:hook-compiler-table -->

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

- **Guard parity** — native role emission is closed across all adapters (Windsurf via workflows). Within P2's three-policy set, guard parity is intentionally partial: Copilot and Codex get all three verified portable guards, Cursor and Gemini get review continuation, and unsupported decisions remain explicit rule fallbacks. Separately, full Codex retains its session-state Stop guard and full Gemini retains output-cap.
- **Windsurf / Devin Desktop** — its asynchronous post-response hook cannot continue the completed turn, so Stop-style enforcement cannot be built from the verified contract; it also has no desktop scheduler for a Reflector job.

Smaller residuals: Gemini/Codex scope rules by nested-file hierarchy rather than glob-on-file-touch; Gemini has no built-in scheduler (use the official GitHub Action); Copilot's coding agent exposes no transcript API.

What you KEEP everywhere (unchanged):

- All rule text, including the vendor-neutral difficulty routing contract.
- All doc templates (five top-level state/index files plus canonical
  specs/plans/architecture/research seeds).
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
