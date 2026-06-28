# COMPATIBILITY MATRIX — CONDUCTOR per tool

This matrix describes which CONDUCTOR features are supported by each target tool. ✅ = native support, ⚠️ = partial / requires manual work, ❌ = not supported.

> **Status note**: ratings below are the *theoretical/spec* level based on each tool's documented capabilities as of 2026-05-03. Verified-by-real-install column will be added per tool as the corresponding adapter ships in P1-P3.5.

## Feature support matrix

| Feature | Claude Code | Cursor | Copilot | Gemini CLI | Codex | Windsurf |
|---|---|---|---|---|---|---|
| **Sub-agent dispatch** (Plan → delegate → verify) | ✅ Agent tool | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Hooks** (PreToolUse / Stop / etc.) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Model routing** (Opus / Sonnet / Haiku triage) | ✅ per-call `model:` arg | ❌ (single model per session) | ❌ | ❌ | ❌ | ❌ |
| **Lazy-loaded rules** (load only when matching files touched) | ✅ paths front-matter | ✅ `globs:` on `.mdc` | ✅ `applyTo:` | ❌ single file | ❌ single file | ⚠️ directory-based |
| **Always-loaded baseline** | ✅ `CLAUDE.md` | ✅ `.cursorrules` | ✅ `applyTo: '**'` | ✅ `GEMINI.md` | ✅ `.codex/codex.md` | ✅ `.windsurfrules` |
| **Slash commands** | ✅ | ⚠️ partial (project commands) | ❌ | ❌ | ❌ | ❌ |
| **Custom agents (named, named with system prompts)** | ✅ `.claude/agents/*.md` | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Skill / plugin ecosystem** | ✅ | ⚠️ (rules-only) | ⚠️ MCP partial | ⚠️ tools | ❌ | ❌ |
| **Per-user persistent memory directory (built-in)** | ✅ `~/.claude/projects/.../memory/` | ❌ (DIY) | ❌ (DIY) | ❌ (DIY) | ❌ (DIY) | ❌ (DIY) |
| **In-repo doc templates work as-is** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Spec-as-you-go enforcement (auto-block)** | ✅ Stop hook | ❌ rule reminder only | ❌ rule reminder only | ❌ rule reminder only | ❌ rule reminder only | ❌ rule reminder only |
| **Two-stage code review enforcement** | ✅ Stop hook reminders | ❌ rule reminder only | ⚠️ Copilot PR review (different mechanism) | ❌ rule reminder only | ❌ rule reminder only | ❌ rule reminder only |
| **Bilingual rule support (한/영)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Tier assignment

| Tier | Tools | Definition |
|---|---|---|
| **T1 — Full** | Claude Code, Cursor | Lazy rule loading works natively; output matches the universal intent closely. Cursor lacks sub-agents but compensates with strong rule scoping. |
| **T2 — Good** | Copilot, Gemini CLI | Rule installation works; Copilot has scoping but no chat-session memory; Gemini scoping is bundled. |
| **T3 — Basic** | Codex, Windsurf | Rule text installs as a single bundle; lazy loading limited; sub-agents/hooks not available. |

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

- **Sub-agent dispatch** — orchestrator role becomes a manual practice, not enforced.
- **Stop hook spec-as-you-go enforcement** — discipline becomes self-policed.
- **Per-call model routing** — you're locked to one model per session.
- **Custom agent slash commands** — replaced by manual prompts.

What you KEEP:

- All rule text (operations, coding-conventions, token-economy, spec-as-you-go, model-routing).
- All doc templates (CURRENT_WORK, REMAINING_TASKS, PLANS, TASKS, INDEX, specs/_example).
- The 4-type memory pattern (you maintain the directory yourself).
- The Plan → Architecture → Tasks → Impl → Review → Spec phase definitions.

The discipline is portable. The enforcement is not.

## Verification status

| Adapter | Adapter spec written | Transform script written | Format validator | Per-IDE smoke (manual) | Real install verified | Quirks documented |
|---|---|---|---|---|---|---|
| Claude Code | ✅ (P0) | ✅ (SHIPPED v0.2 P1) | ✅ `validate-adapter-output.sh claude` PASS (2026-05-10) | n/a (Claude Code CLI itself is the runtime; covered by orchestrator harness) | ✅ (7 uninstall verification cases 2026-05-10, ADR-020) | ✅ (ADR-019, ADR-020, IDE-COMPATIBILITY-NOTES § Claude) |
| Cursor | ✅ (P0) | ✅ (SHIPPED v0.2, ADR-021) | ✅ `validate-adapter-output.sh cursor` PASS (2026-05-10) | ⏳ pending (Cursor smoke — see IDE-SMOKE-TESTING § 1) | ⚠️ Synthetic-target smoke + format-validator PASS (4 cases 2026-05-10); real-IDE empirical verification deferred to adopter feedback | ✅ (ADR-021, IDE-COMPATIBILITY-NOTES § Cursor) |
| Copilot | ✅ (P0) | ✅ (SHIPPED v0.2, ADR-022) | ✅ `validate-adapter-output.sh copilot` PASS (2026-05-10) | ⏳ pending per IDE: VS Code (§ 2), Cursor+Copilot (§ 3), Windsurf (§ 4), JetBrains (§ 5), Neovim (§ 6) | ⚠️ Synthetic-target smoke + format-validator PASS (3 cases 2026-05-10 — fresh / adopter / per-rule); per-IDE real smoke deferred to adopter feedback | ✅ (ADR-022, IDE-COMPATIBILITY-NOTES § Copilot) |
| Gemini CLI | ✅ (P0) | ✅ (SHIPPED v0.2 — `adapters/gemini/transform.sh` → `GEMINI.md` + `.gemini/styleguide.md`) | ✅ `validate-adapter-output.sh gemini` PASS | n/a (CLI runtime) | ⚠️ Emit-verified (format-validator + synthetic-target smoke PASS); live runtime consumption by Gemini CLI still pending — see `docs/ADAPTER-LIVE-VERIFICATION.md` | ✅ (IDE-COMPATIBILITY-NOTES § Gemini) |

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
| Codex | ✅ (P0) | ✅ (SHIPPED v0.2 — `adapters/codex/transform.sh` → `AGENTS.md`) | ✅ `validate-adapter-output.sh codex` PASS | n/a (CLI runtime) | ⚠️ Emit-verified (format-validator + synthetic-target smoke PASS); live runtime consumption by Codex still pending — see `docs/ADAPTER-LIVE-VERIFICATION.md` | ✅ (IDE-COMPATIBILITY-NOTES § Codex) |
| Windsurf | ✅ (P0) | ✅ (SHIPPED v0.2 — Windsurf now has its OWN `adapters/windsurf/transform.sh` → `.windsurfrules` + `.windsurf/rules/*.md`, in addition to being reachable via the Copilot adapter) | ✅ `validate-adapter-output.sh windsurf` PASS | ⏳ adopter follow-up / live-pending (IDE-SMOKE-TESTING § 4) | ⚠️ Emit-verified (format-validator + synthetic-target smoke PASS); live runtime consumption by Windsurf still pending — see `docs/ADAPTER-LIVE-VERIFICATION.md` | ✅ (IDE-COMPATIBILITY-NOTES § Windsurf) |
