# DESIGN DECISIONS — CONDUCTOR

ADR-style decision records. Each entry: Status / Context / Decision / Consequences / Alternatives considered.

---

## ADR-001 — 3-layer architecture (Universal / Adapter / Tool-native)

**Status**: Accepted (2026-05-03, v0.2 foundation reset).

**Context**: v0.1 hard-coded a Claude-only output. Adding multi-tool support by retrofitting adapter logic alongside Claude-shaped templates would have made every change a 2-place edit. The user explicitly asked to set the architectural direction and establish thorough documentation before writing any code — implying clean architectural separation, not glued-on extension.

**Decision**: Three layers with single responsibility each.
- **Layer 1 (`core/`)** — universal, tool-agnostic source-of-truth. Plain markdown, zero tool references.
- **Layer 2 (`adapters/<tool>/`)** — per-tool transform script. Reads Layer 1, writes tool-native files.
- **Layer 3** — tool-native features (sub-agents, hooks). NOT polyfilled across tools; documented honestly.

**Consequences**:
- Adding a new tool = write one adapter; Layer 1 untouched.
- Changing rule content = edit Layer 1; all adapters benefit on next install.
- Cannot fake Claude-only features on other tools (deliberate).
- Two-place edit only when a tool gets a new native feature that requires adapter changes.

**Alternatives considered**:
- *Single template with adapter overrides.* Rejected — every Layer-1 change requires N override edits.
- *Tool-native as plugins on a shared event bus.* Rejected — over-engineered; CONDUCTOR is files-on-disk.
- *Skip Layer 3, claim feature parity.* Rejected — dishonest, fragile, will break.

---

## ADR-002 — Per-adapter transform.sh (not central script)

**Status**: Accepted.

**Context**: Two valid options for the transform layer: (a) one central script with per-tool branches, or (b) one script per adapter, each focused on one tool.

**Decision**: One `transform.sh` per adapter under `adapters/<tool>/transform.sh`.

**Consequences**:
- Adapter authors can specialize; no need to understand other adapters.
- A bug in the Cursor adapter cannot affect the Claude adapter.
- Higher repetition risk — shared helpers go in `adapters/_shared/` if they emerge organically (do NOT design upfront).
- Easier community contributions: a new contributor adds one directory and one file.

**Alternatives considered**:
- *Central `transform.sh` with `case $TARGET in` branches.* Rejected — any change touches everyone's tool.
- *Plugin module loader (Node.js).* Rejected — adds runtime dependency for what is a text-transformation problem.

---

## ADR-003 — Universal rules in markdown (not YAML/JSON)

**Status**: Accepted.

**Context**: Adapters need to read Layer-1 rule content and emit tool-specific files. Rule content could be in structured YAML/JSON (parseable, queryable) or markdown (human-readable, what every tool already consumes).

**Decision**: Plain markdown with optional YAML front-matter (used only for adapter routing hints like `paths:`, `tier:`, `tags:`).

**Consequences**:
- Rules are human-readable and authorable without tooling.
- Adapters do `cat` + light front-matter parsing; no JSON-schema burden.
- Cross-tool inconsistency in front-matter syntax is hidden inside each adapter (e.g., Claude wants `paths:`; Cursor wants `globs:`; Copilot wants `applyTo:`).
- We give up structured queryability ("show me all rules tagged 'security'"). Acceptable; nobody asked for it.

**Alternatives considered**:
- *YAML/JSON canonical with markdown rendered output.* Rejected — extra build step, alienates non-tooled contributors.
- *Bare text files (no front-matter).* Rejected — adapters need routing hints somewhere.

---

## ADR-004 — Sub-agents stay Claude-only (don't fake on Cursor)

**Status**: Accepted.

**Context**: Sub-agent dispatch (orchestrator → specialized agents) is a Claude-Code-only feature. Other tools have a single chat session. We could try to simulate sub-agents on Cursor by spawning Cursor CLI processes from a parent script.

**Decision**: We will NOT simulate sub-agents on non-Claude tools. The orchestrator pattern is documented universally; on non-Claude tools, the human plays orchestrator manually.

**Consequences**:
- Honest documentation: users know what they are getting per tool.
- No fragile process-spawning code to maintain.
- Power-loss is real: multi-step delegation flows are slower and lossier on non-Claude tools.
- The "universal" workflow remains universal in *intent*; the *mechanism* degrades gracefully to manual.

**Alternatives considered**:
- *Spawn Cursor CLI per sub-agent dispatch.* Rejected — startup cost, fragile to Cursor CLI changes, leaks complexity.
- *Use OpenRouter / unified API + custom CLI.* Rejected — out of scope; not what CONDUCTOR is.

---

## ADR-005 — Memory pattern is documentation-only for non-Claude tools

**Status**: Accepted.

**Context**: Claude Code has a built-in per-project memory directory at `~/.claude/projects/<encoded-path>/memory/`. Other tools have nothing equivalent.

**Decision**: `core/memory-pattern/` documents the 4-type pattern (user / feedback / project / reference) and how to apply it. On non-Claude tools, the user creates a memory directory wherever they want (commonly `.memory/` at project root, gitignored). The adapter installs the pattern README + an example, but the directory is the user's responsibility.

**Consequences**:
- Pattern is portable; mechanism is per-tool.
- Non-Claude users have to be more deliberate about saving memory entries.
- We avoid mandating a specific path on tools that don't have a convention.

**Alternatives considered**:
- *Mandate `.memory/` everywhere.* Rejected — the dotfile crowd hates, the no-dotfile crowd hates, neither wins.
- *Skip memory pattern for non-Claude tools.* Rejected — the pattern is the most-praised part of v0.1; deprive nobody.

---

## ADR-006 — Bilingual (한/영) is first-class

**Status**: Accepted.

**Context**: CONDUCTOR's primary author is Korean. Korean solo-dev community is active and underserved by English-only tools. But contributors will be majority English.

**Decision**:
- `README.md` is bilingual, Korean section first.
- `VISION.md`, `ROADMAP.md`, `docs/*` are English (contributor-accessible).
- Memory examples and `core/universal-rules/` may include Korean phrases inline ("위반 시 STOP 후 fix course") preserved from origin.
- Marketing material, blog posts, launch tweets: bilingual at v1.0.
- Adapter scripts are English (code is English).

**Consequences**:
- Korean adopters get a native-feeling onboarding.
- English contributors are fully supported on all internal docs.
- Some duplication / translation drift risk in `README.md`. Acceptable for the headline doc.

**Alternatives considered**:
- *English-only with Korean as later translation.* Rejected — defeats the moat.
- *Bilingual everywhere.* Rejected — too much maintenance for internal docs.

---

## ADR-007 — MIT license + LFamily Labs LLC ownership (vs source-available)

**Status**: ~~Accepted (revised 2026-05-10 — copyright holder clarified)~~ — **SUPERSEDED by ADR-029 (2026-06-28)**: license changed MIT → Apache 2.0 (code) + CONDUCTOR-name trademark. The ownership decision (LFamily Labs LLC) stands.

**Context**: The discipline embedded in CONDUCTOR is hard-won and could be commercialized (paid tier, hosted dashboard, etc.). MIT means anyone can fork and ship a commercial version without sharing back. The project is an asset of LFamily Labs LLC; explicit attribution to the LLC, not to an individual, makes ownership unambiguous for downstream contributors and forks.

**Decision**: MIT, permissive, no restrictions. Copyright holder = **LFamily Labs LLC** (not individual). Standard OSS conventions — anyone may use, modify, sublicense, and sell, including commercial forks. No trademark restriction beyond standard MIT terms.

**Consequences**:
- Maximizes adoption (no license-anxiety for corporate users).
- Aligns with "files-on-disk, no telemetry" non-goals.
- LFamily Labs LLC retains full freedom to use Conductor commercially in its own products (the reference project and others) — same MIT terms apply to LFamily as to anyone else. No dual-licensing required.
- Anyone can fork-and-sell. Accepted — Conductor is a thin discipline framework, not a moat. Differentiation lives in the maintained branch + community, not legal restrictions.

**Alternatives considered**:
- *Apache 2.0.* Acceptable but adds patent-grant complexity for a pure-text framework. MIT is simpler.
- *BSL / Source-available.* Rejected — friction to adoption, not aligned with project values.
- *Copyleft (GPL).* Rejected — viral nature scares corporate adopters and adds no value here.

---

## ADR-008 — No telemetry (vs Cursor's opt-in)

**Status**: Accepted.

**Context**: Most coding tools (Cursor, Copilot, etc.) phone home with usage telemetry. CONDUCTOR is a pure file-on-disk framework; it doesn't run as a process. But future installer / CLI could phone home.

**Decision**: Zero telemetry. Ever. The CLI's only network access is `git clone` and (in P4) `npm install`. No usage stats, no opt-in tracking, no anonymous metrics.

**Consequences**:
- We never know how many people use CONDUCTOR.
- Trust is high — users can audit the install script line-by-line.
- We cannot optimize based on usage data; we optimize based on issue reports + GitHub stars + community feedback.
- Aligns with "files-on-disk" identity.

**Alternatives considered**:
- *Opt-in anonymous installs counter.* Rejected — opt-in metrics suffer from self-selection bias and add a network dependency.
- *Phone-home with detailed stats.* Rejected — antithetical to the project.

---

## ADR-009 — Universal-rules organized into 5 bundles

**Status**: Accepted (2026-05-06, v0.2 P1 entry).

**Context**: 17 ABSOLUTE rules and ~6 recurring strong rules emerged from production use of the originating project. They needed a layout that is (a) human-readable when read top-to-bottom, (b) cache-friendly when injected as a prefix to every session, and (c) scoped enough that grep/glob routing in tools that support `paths:` / `globs:` / `applyTo:` frontmatter does not blow up.

**Decision**: Group all universal rules into 5 markdown files inside `core/universal-rules/`:
- `workflow.md` — plan-first, docs-first, ad-hoc work order, process-over-speed, never-skip-absolute.
- `spec-as-you-go.md` — same-turn spec update, real-time docs sync, test-coverage sync.
- `quality-gates.md` — pre-commit review, pre-merge review, verify-after-changes.
- `operations.md` — branch strategy patterns, push timing, completed-tasks delete, dev/prod sync.
- `meta-discipline.md` — process-over-speed, framework-originality, absolute-rules-never-skip, ACT-WITH-DECLARATION + AMB triggers, verify-before-recommending, token-economy reference, model-routing reference.

**Consequences**:
- Adapter `transform.sh` emits 5 files (or concatenates them for single-file tools like Gemini / Codex).
- Cache prefix is short (~6K tokens combined) → high cache-hit rate for Claude prompt caching.
- Searching by category requires grep, but the 5 file names are mnemonic enough that contributors learn them in one session.
- Project-specific concerns (web↔mobile parity, i18n, monorepo, branch strategy specifics, auto-mock data, coding-conventions specifics) live in `core/recipes/` as opt-in instead of forcing every adopter to inherit them.

**Alternatives considered**:
- *8 files (one per category W/Q/P/O/M plus ambiguity / token / routing).* Rejected — too granular for adoption; 8 file names is hard to memorize.
- *Single `RULES.md` monolith.* Rejected — kills file-glob scoping and produces unwieldy diffs.
- *3 files (workflow / quality / meta).* Rejected — quality-gates and spec-as-you-go are independently triggered and shouldn't share a file.

---

## ADR-010 — Centralized + Role-Specialized Orchestrator pattern (default)

**Status**: Accepted.

**Context**: Several multi-agent patterns are viable: centralized supervisor, hierarchical SOP-driven, peer-to-peer chat, reactive state-machine, pipeline waterfall. We needed one universal default that maps cleanly to every supported tool — including tools without native sub-agent dispatch.

**Decision**: Centralized + Role-Specialized with a **flat-with-leader** topology.
- A single `orchestrator` thread is the only user-facing leader.
- 6 universal roles (planner, builder, reviewer, helper, designer, scribe) act as 1:1 dispatch targets.
- Sub-agents MUST NOT dispatch other sub-agents (no nested dispatch). If multi-step work is needed, the sub-agent returns intermediate result; orchestrator decides next dispatch.
- On tools without native sub-agent dispatch, the orchestrator + helper roles collapse into **Single-Agent Mode**: the human user plays the role separator manually, guided by the rule text.

**Consequences**:
- Solo-dev mental model preserved (one leader + helpers).
- No nested-dispatch context blow-up.
- Cross-tool consistent: same rule text describes the pattern; only the dispatch mechanism changes per tool.
- Peer-to-peer / state-machine / pipeline patterns are documented in `docs/CONDUCTOR-V0.2-DESIGN.md` for context but not adopted as default.

**Alternatives considered**:
- *Hierarchical SOP-driven (manager → role agents).* Rejected — adds a layer that solo dev doesn't need.
- *Peer-to-peer conversation.* Rejected — emergent behavior, token blow-up, hard to reproduce.
- *Reactive state-machine (graph + checkpoints).* Rejected — over-engineered for files-on-disk framework. CURRENT_WORK.md already serves as a simple checkpoint.

---

## ADR-011 — ACT-WITH-DECLARATION default + AMB triggers force ASK

**Status**: Accepted.

**Context**: LLMs trained with RLHF tend to resolve ambiguity by guessing rather than asking. Production experience showed that silent guesses cause downstream rework when the guess is wrong, but asking on every turn produces fatigue. We needed a policy that minimizes both wrong guesses and unnecessary questions.

**Decision**: Default behavior = **ACT-WITH-DECLARATION** (proceed with best-guess, surface the assumption in the response prefix). Override = **ASK (multiple-choice)** when any of 7 ambiguity triggers fire:
- AMB-1 deictic references ("this", "like before", "similar")
- AMB-2 unspecified scope (single vs all, web vs mobile)
- AMB-3 external system invocation (db push, payment ops, schema migration)
- AMB-4 merge / push to protected branch
- AMB-5 design decisions (color, layout, copy tone)
- AMB-6 dependency / library addition
- AMB-7 user manual action required (env vars, dashboard configuration)

ASK responses use a multiple-choice template (option A / B / C + free-text + recommended default) so the user can reply in seconds.

**Consequences**:
- Irreversible / high-cost decisions are protected by forced ASK.
- Routine work proceeds without nagging — the declaration prefix gives the user a one-glance catch.
- AMB triggers are extensible: a new trigger gets added to `meta-discipline.md` when production use surfaces a missed category.

**Alternatives considered**:
- *ASK by default everywhere.* Rejected — produces fatigue, slows trivial tasks.
- *ACT only, never ASK.* Rejected — irreversible operations need explicit confirmation.
- *Confidence threshold (numeric).* Rejected — calibration is unreliable across models / tasks; trigger catalog is more deterministic.

---

## ADR-012 — Anthropic prompt caching is an actively-recommended pattern (Claude adapter)

**Status**: Accepted.

**Context**: Anthropic prompt caching can reduce input cost by ~90% and latency by ~85% for repeated prefixes. It requires a `cache_control` marker placed deliberately at the boundary between cacheable prefix and per-turn variable content. Most adopters won't discover this on their own.

**Decision**: The Claude adapter explicitly recommends prompt caching in the generated `CLAUDE.md` and ships a guide at `docs/PROMPT-CACHING-GUIDE.md` covering:
- Recommended prefix order: universal-rules → recipe-rules → project memory index → task-specific brief.
- Where to place the `cache_control: { type: "ephemeral" }` boundary.
- Cache hit rate SLA (≥95%, per ADR-014) and how to measure it via `tools/measure-tokens.sh`.

**Consequences**:
- Adopters who follow the guide get immediate cost / latency wins on repeated turns.
- Non-Claude adapters explicitly note that prompt caching is unavailable (no equivalent native feature) — `docs/COMPATIBILITY-MATRIX.md` already records this.
- The guide is implementation-agnostic at the SDK level; we provide structure and order, not boilerplate code.

**Alternatives considered**:
- *Make it opt-in (separate doc, not referenced from CLAUDE.md).* Rejected — most adopters will miss it; the cost win is too large to bury.
- *Auto-inject `cache_control` markers via transform.sh.* Rejected — markers are SDK-call concerns, not file-on-disk concerns. Out of scope for transform.

---

## ADR-013 — 6 universal roles + 6 project-specific recipes

**Status**: Accepted.

**Context**: The originating project had 8 specialized agents; 2 of them (mailer, translator) were domain-specific. We needed to draw a clear line between universal (every adopter inherits) and project-specific (opt-in via recipe).

**Decision**:
- **6 universal roles** in `core/roles/`: planner, builder, reviewer, helper, designer, scribe.
- **6 project-specific recipes** in `core/recipes/` (opt-in): web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions.
- Each role file uses CONDUCTOR's own frontmatter schema (`role`, `purpose`, `default_model`, `must_do`, `must_not_do`, `output_format`, `stop_condition`).
- Each recipe documents when it applies, what files it touches, and which universal rules it layers on top of.

**Consequences**:
- Minimum-viable installation is small (6 roles + 5 universal-rules). Adopters add recipes only as their project demands them.
- Multi-locale or web↔mobile parity adopters opt in to those recipes explicitly — no hidden assumptions.
- The 2 specialized agents from the originating project (mailer, translator) become adopter-specific roles that live in the adopter's own `.claude/agents/` directory; CONDUCTOR core does not ship them.

**Alternatives considered**:
- *Ship all 8 roles universally.* Rejected — mailer / translator are project-specific; forcing them dilutes the universal vocabulary.
- *Ship 4 roles only (planner / builder / reviewer / helper).* Rejected — designer and scribe are universal patterns (every project has UI work and docs sync).
- *Recipe-only, no universal roles.* Rejected — every adopter needs the same 6 baseline roles; no value in making them opt-in.

---

## ADR-014 — Cache hit rate ≥ 95% as Conductor SLA

**Status**: Proposed (2026-05-07).

**Context**: P1.5 baseline measurement of the reference project (8 sessions, 37,763 turns) recorded 100% cache hit rate. Claude Code's built-in prompt caching is fully active by default — the pre-measurement assumption of "~0% cache hit" was incorrect. However, the 100% figure is specific to a mature project with a well-established CLAUDE.md prefix. New users applying Conductor for the first time may unknowingly introduce anti-patterns (large non-cacheable injections, per-turn prefix variation) that drop cache hit rate significantly.

**Decision**: Conductor establishes a 95% cache hit rate floor as its SLA. Projects using the Claude adapter that fall below 95% are considered misconfigured. The gap between 95% and 100% accounts for session-start cache-cold turns and edge cases that are not worth optimizing.

- The `stop-cache-hit-check.sh.template` hook (P1.7) alerts when the last-session hit rate drops below 95%.
- Anti-pattern catalog (P1.6) documents the 7 patterns that cause cache hit rate degradation.
- `docs/KPI.md` is the authoritative measurement source; re-measured after every major change to hooks or rule files.

**Consequences**:
- P1.6 anti-pattern catalog and P1.7 stop hook are prerequisite deliverables for this ADR to be enforced.
- New-user onboarding must include a first-session measurement step (see ADR-015).
- Non-Claude adapters are exempt — prompt caching is a Claude-only capability; `docs/COMPATIBILITY-MATRIX.md` marks it as such.

**Alternatives considered**:
- *Target 100%.* Rejected — 100% is achievable only in steady-state sessions; cold starts are inherently below 100%.
- *No SLA; treat as best-effort.* Rejected — without a numeric floor, the anti-pattern catalog has no enforcement hook.
- *80% floor.* Rejected — too permissive; an 80% hit rate means 20% of turns pay full input token cost, which is significant at scale.

---

## ADR-015 — KPI baseline measurement schedule

**Status**: Proposed (2026-05-07).

**Context**: Without a measurement schedule, KPI regression goes undetected between milestones. The P1.5 baseline was taken once; re-measurement was planned for 1 week post-P2. An explicit schedule is needed so onboarding new users and adding new adapters both trigger measurement automatically.

**Decision**:
1. **Initial baseline**: run `tools/measure-tokens.sh --latest` immediately after installing the Claude adapter on a new project. Record to `docs/data/baseline-<date>.csv`.
2. **1-week re-measurement**: run again after 1 week of active use. Compare against initial baseline. If any KPI target is missed, trigger anti-pattern diagnosis using `core/anti-patterns/`.
3. **Per-milestone re-measurement**: run at the end of every major Conductor milestone (P1.7, P2, P3, P4).
4. **Adapter-specific baselines**: when a non-Claude adapter is first used in production, take a baseline for that environment separately (tool call patterns differ by tool).

The measurement tool outputs a structured summary that can be diffed against `docs/KPI.md` targets.

**Consequences**:
- Onboarding wizard (a future P1.7 dispatch or P4 CLI feature) must include a `--measure-baseline` flag.
- `docs/KPI.md` gains a "re-measurement history" table updated at each scheduled measurement.
- Non-Claude adapters lack cache hit measurement (no JSONL equivalent); their KPI set is limited to tool calls and output tokens, measured via tool-specific logging.

**Alternatives considered**:
- *Continuous measurement (every session).* Rejected — too noisy; daily fluctuations are not actionable.
- *Monthly schedule only.* Rejected — a month is too long to detect an anti-pattern introduced by a new hook or rule change.
- *Manual-only, no schedule.* Rejected — without a schedule, re-measurement is skipped under time pressure.

---

## ADR-016 — the reference project ↔ Conductor양방향 동기화 ABSOLUTE

**Status**: Accepted (2026-05-07, 사용자 명시 룰).

**Context**: the reference project is Conductor's reference project and primary dogfood environment. Hooks, measurement tools, universal rules, and anti-pattern patterns developed for Conductor are validated in production via the reference project first. Conversely, improvements discovered in the reference project (new hook templates, revised rule text, KPI findings) must propagate back into Conductor core. Without a formal synchronization rule, the two projects diverge silently.

**Decision**: The two projects share the same efficiency standard, hook templates, and measurement tools. Any addition in either direction triggers an immediate mirror update in the other:

- New hook template in `conductor/core/hooks/` → install in `the reference project's repo/.claude/hooks/` in the same PR.
- New anti-pattern discovered in the reference project → add to `conductor/core/anti-patterns/` before closing the session.
- KPI measurement result in the reference project → update `conductor/docs/KPI.md` in the same commit batch.
- Rule text change in `conductor/core/universal-rules/` → validate against the reference project's active session; if behavior differs, reconcile before merging.

**Enforcement**: PR template for conductor repo includes a mandatory checkbox: "the reference project sync: N/A | Done | Pending (tracked in issue #__)". A sync is "N/A" only for adapters that have no equivalent in the reference project (Cursor, Copilot, Gemini).

**Consequences**:
- Any new hook or skill added to Conductor must include a measured cache impact (before/after using `measure-tokens.sh`). ADR must be filed if the impact exceeds ±5% on any KPI.
- Increased coordination overhead between the two repos — acceptable given both are maintained by the same developer.
- "양방향" (bidirectional) sync is absolute; one-directional cherry-pick is not sufficient.

**Alternatives considered**:
- *One-directional (Conductor → the reference project only).* Rejected — production discoveries in the reference project are the most valuable signal; losing them degrades Conductor quality.
- *Sync on major milestones only.* Rejected — milestone gaps allow anti-patterns to accumulate. Real-time sync is the standard.
- *Separate memory entry only (no ADR).* Rejected — memory entries are per-session reminders, not durable architectural decisions. This rule rises to ADR level.

---

## ADR-017 — the reference project ecaf0c2 sync — selective port boundary

**Status**: Accepted (2026-05-08).

**Context**: the reference project commit `ecaf0c2` ("full optimization + auto-load verified") compressed `CLAUDE.md` 185→108, slimmed `AGENT.md` 87→30, added `.claude/rules/project-context.md` (paths-glob auto-load), inserted `permissions.allow` (26 commands) into `.claude/settings.json`, registered a 4th Stop hook (`stop-r9-sunset-check.sh`), and extended `stop-session-log-check.sh` with a "Check 4" plan-first enforcement (5+ ts/tsx changes + 0 `.plan.md` → block). Per ADR-016, every the reference project improvement must be evaluated for Conductor port. This ADR records the per-item port decision so future sync sessions don't re-litigate the boundary.

**Decision**: Conductor accepts the cross-applicable subset and explicitly rejects the the reference project specific subset.

**Accepted (ported into Conductor on 2026-05-08)**:

1. **Plan-first hook check** — added to `core/hooks/stop-session-log-check.sh.template` as Check 3 (Conductor numbering; equivalent to the reference project's Check 4). Threshold parametrized via `${CONDUCTOR_PLAN_THRESHOLD:-5}` for project-level tuning. Fires post-hoc when 5+ source-glob files change without any `.plan.md` in the same diff.
2. **Permissions allowlist (24 commands, Conductor-tuned)** — added to `archive/v0.1/template/.claude/settings.template.json` and embedded in `adapters/claude/transform.sh` Step 4. the reference project's 26-command list pruned of `npx vitest`, `npx expo`, and other the reference project specific entries; added `bash -n:*` for shell-script syntax checks (relevant to Conductor adapter dev).
3. **`.claude/settings.json` emission in transform.sh** — previously only the `archive/v0.1/` template carried settings; the live adapter never emitted one. Closing this gap means consumer projects get the allowlist + hooks registry automatically.
4. **Forward-compatible hook discovery** — Step 4 hook list now iterates over a 5-item array (`pretool-agent-routing`, `stop-session-log-check`, `stop-r6-review-check`, `stop-cache-hit-baseline-check`, `pretool-large-file-read-guard`) and skips silently when a template is absent. P1.7 hooks therefore activate automatically once their templates land in `core/hooks/`.

**Rejected (the reference project specific)**:

1. **`CLAUDE.md` compression** — Conductor's `CLAUDE.md` is 139 lines and structurally distinct (R1-R6 about not modifying the reference project / sanitization / multi-tool first), not a candidate for the same dedup pass.
2. **`AGENT.md` slim pointer** — Conductor has no `AGENT.md`; the consumer-facing pointer file is generated per-tool by adapters, which is the correct shape.
3. **`.claude/rules/project-context.md`** — would re-introduce project facts (tech stack / monorepo / env / commands) into Conductor, but Conductor IS the framework and has no project facts to record. the reference project is the consumer; Conductor is the producer.
4. **`paths: ["**"]` frontmatter on source rule files** — would break the multi-tool abstraction. Conductor's `transform.sh` already injects `paths:` on Claude emit, `globs:` on Cursor emit, `applyTo:` on Copilot emit. Source rules MUST stay tool-agnostic (`applies_to: ["all-tools"]`).
5. **`stop-r9-sunset-check.sh`** — the reference project R9 = GitHub Actions monthly cap sunset (2026-06-01). Conductor has no equivalent CI quota expiration.
6. **R9 body absorption into `operations.md`** — same reason as 5. Adding it would re-introduce sanitization debt that Conductor's whole purpose (R1+R2) is to avoid.

**Consequences**:
- Conductor consumer projects (those that run `bash adapters/claude/transform.sh`) now get a `.claude/settings.json` with permissions allowlist by default — fewer permission prompts during normal orchestration. Migration: existing consumers with a hand-written `settings.json` are left in place (the adapter detects + skips).
- The plan-first hook check makes W1.1 (Medium/Large scope requires `.plan.md`) automatically enforceable on Claude. Cursor / Copilot / Gemini adapters will need rule-text reminders since they lack hooks (already documented in `meta-discipline.md` cross-tool table).
- Forward-compat hook discovery means P1.7's two new hooks ship automatically once their templates land in `core/hooks/`, without further `transform.sh` edits. This is the intended shape; ADR-016 sync cadence stays low-friction.

**Alternatives considered**:
- *Port the entire the reference project diff verbatim.* Rejected — would corrupt Conductor's multi-tool abstraction and re-introduce sanitization debt (rejected items 1-6).
- *Skip the sync entirely.* Rejected — violates ADR-016 (bidirectional sync ABSOLUTE).
- *Port Check 4 only, defer settings.json.* Rejected — settings.json emission gap was already a latent bug (the live adapter lacked what the v0.1 template had); fixing it together is the right scope.


---

## ADR-018 — the reference project 2026-05-09 hookify rule sync — port boundary + adapters/claude/hookify-templates/

**Status**: Accepted (2026-05-09).

**Context**: On 2026-05-09, the originating reference project added 25 `.claude/hookify.*.local.md` rules using the hookify Claude Code plugin. Hookify intercepts Bash, file-edit, prompt, and stop events at runtime and injects warning/blocker messages based on YAML-frontmatter rule definitions. Per ADR-016 (bidirectional sync ABSOLUTE), every reference-project addition is evaluated for Conductor port. Hookify is a Claude-only feature; per R3 (multi-tool first), Claude-only assets belong under `adapters/claude/`, not in `core/`.

**Decision**: Conductor adds a new directory `adapters/claude/hookify-templates/` containing 11 sanitized, placeholder-ized templates (the cross-applicable subset of the 25). `adapters/claude/transform.sh` gains a Step 4.5 that copies templates to `<target>/.claude/hookify.<name>.local.md` with placeholder substitution, mirroring the existing hook-template pattern. The remaining 14 reference-project rules are SKIPPED — they encode stack-specific assumptions (BaaS RLS, payment provider, email provider, UI library, icon library, design tokens, dual-platform parity, project-specific paths, CI-quota windows, **and branch-protection policy**) that would corrupt Conductor's tool-agnostic abstraction.

**Revision 2026-05-09 (post-publish)**: `block-direct-push-protected-branch` removed from accepted list per user clarification. Branch-strategy is project-specific: trunk-based projects (Conductor itself) push to `main` directly; multi-stage pipelines (the reference project: `develop → release → main`) protect `main`/`release`. Adopters configure per their own pipeline. Force-push protection retained — universal safety even on trunk.

**Accepted (11 ported as templates, 2026-05-09)**:

| Template | Universal trigger |
|---|---|
| `block-completion-claim-without-push` | False completion claim without push evidence |
| `block-force-push-protected-branch` | Force push to protected branch |
| `warn-current-work-without-remaining-tasks` | Cross-doc flip pattern (CURRENT_WORK ↔ REMAINING_TASKS) |
| `warn-plan-spec-without-remaining-tasks` | 4-spot flip on plan/spec edit |
| `warn-on-gh-pr-merge` | PR merge → 4-spot flip reminder |
| `warn-stop-commit-without-current-work` | Same-turn docs sync after commit |
| `warn-commit-without-pre-commit-review` | Q1 (quality-gates) reminder |
| `warn-gh-pr-create-without-pre-merge-review` | Q2 (quality-gates) reminder |
| `warn-user-manual-completion` | User manual report → docs sync trigger |
| `warn-any-type-added` | TypeScript `: any` discipline (recipe-aligned) |
| `warn-console-direct` | Logger-helper discipline (recipe-aligned) |

Each template body cites the framework's universal rules (`workflow.md`, `quality-gates.md`, `spec-as-you-go.md`, `core/recipes/coding-conventions.md`) — not vendor or stack specifics. Placeholders (`${CONDUCTOR_PROTECTED_BRANCHES}`, `${CONDUCTOR_CURRENT_WORK_PATH}`, `${CONDUCTOR_REMAINING_TASKS_PATH}`, `${CONDUCTOR_SOURCE_GLOB}`, `${CONDUCTOR_PROJECT_NAME}`) are substituted at install time by `substitute_hookify_template()`, a non-`chmod` variant of the existing `substitute_template()` helper.

**Rejected (14 reference-project specific)**:

0. **`block-direct-push-protected-branch`** (revision 2026-05-09) — Branch-protection is project-specific: Conductor itself is trunk-based with main as the active development branch; the reference project uses `develop → release → main` because it deploys via Vercel. Adopters add their own direct-push protection rules in `.claude/hookify.*` based on their pipeline. Universal safety only on force-push (retained).
1. **`block-r9-commit-missing-skip-ci`** — Reference-project specific GitHub Actions monthly-cap window. Already-rejected twin in ADR-017.
2. **`block-service-role-key-in-client`** — BaaS-specific service-role-key string. Conductor's recipes don't mandate any specific BaaS.
3. **`warn-create-table-without-rls`** — Postgres RLS specific.
4. **`warn-security-definer-without-search-path`** — Postgres `SECURITY DEFINER` specific.
5. **`warn-non-shadcn-ui-import`** — Specific UI library banlist.
6. **`warn-non-lucide-icon`** — Specific icon library.
7. **`warn-raw-color-hex`** — Specific design-token system.
8. **`warn-hardcoded-jsx-text`** — Although i18n is a recipe (`core/recipes/i18n.md`), the rule body is JSX/React + 8-locale specific. Adopters using the i18n recipe can copy this rule from their reference and edit.
9. **`warn-shared-i18n-sync`** — Specific monorepo dual-file path (`packages/shared` + `apps/web/lib/i18n`).
10. **`warn-service-route-without-e2e`** — Reference-project specific paths (`apps/web/lib/services/`, `apps/web/app/api/`).
11. **`warn-email-send-without-list-unsubscribe`** — Specific email provider + RFC 8058 List-Unsubscribe header pattern.
12. **`warn-web-mobile-parity`** — Reference-project dual-platform pair. Recipe `web-mobile-parity.md` covers the principle conceptually.
13. **`warn-mobile-screen-without-test`** — Reference-project mobile path specific.

The 13 rejected rules ARE valuable patterns for projects with the same stack — they belong in the adopter's project-local `.claude/hookify.*` directory, not in framework templates. The framework's responsibility ends at the universal subset.

**Consequences**:

- Conductor consumer projects that run `bash adapters/claude/transform.sh` now receive 12 hookify rules in `<target>/.claude/hookify.*.local.md` automatically. Existing files are NEVER overwritten — adopter customizations win.
- The adapter remains forward-compat: if `adapters/claude/hookify-templates/` is empty or missing, Step 4.5 silently skips. New templates can be added without further `transform.sh` edits.
- Other-tool adapters (Cursor / Copilot / Gemini) do NOT receive hookify equivalents. If those tools add comparable runtime hook plugins, equivalent templates land under their respective adapter directory. Until then, those adapters rely on universal rule text + LLM self-discipline.
- Originality (M1): every template body cites framework universal rules and uses neutral terminology. No reference-project names, no vendor-specific stack mentions, no copy-paste of project-specific past-violation case histories beyond a one-line "origin" note.

**Alternatives considered**:

- *Port all 25 verbatim into a `core/hookify-templates/` directory.* Rejected — half the rules are stack-specific and would corrupt the tool-agnostic abstraction. Plus core/ is shared across all 6 tool adapters; hookify is Claude-only.
- *Port 12 into `core/hookify-templates/` and have only the Claude adapter copy them.* Rejected — same multi-tool corruption issue. The directory location signals "what tool reads this"; placing Claude-only templates in `core/` mis-signals.
- *Skip the sync entirely until other tools adopt runtime hooks.* Rejected — violates ADR-016. Production-validated patterns must propagate to consumer projects via the Claude adapter today, not wait for hypothetical future tool features.
- *Embed the 12 rule bodies directly into `transform.sh` heredocs (no separate template directory).* Rejected — kills readability, prevents adopters from previewing rules before install, and breaks the symmetry with `core/hooks/*.template`.

**Reverse-sync candidates (Conductor → reference project)**: none specific to this sync. The 13 reference-project specific rules in the adopter project are the source-of-truth for adopter-project work; they remain there.

## ADR-019 — Competitive analysis 2026-05-09 cleanup batch (P0b backup expansion + P1a wizard trigger + P1c Superpowers conflict guide)

**Status**: Accepted (2026-05-09).

**Context**: The competitive analysis audit `docs/audits/competitive-analysis-2026-05-09.md` (Superpowers vs Conductor on 7 dimensions) surfaced three actionable gaps that block production-grade adopter trust. Two of them — P0a (Cursor adapter) and P1b (`--uninstall` flag) — are heavy and tracked under separate dispatches. The remaining three (P0b, P1a, P1c) are surface-level and bundled here for batch resolution.

**Decision** (three changes, applied in one commit):

1. **P0b — Generalized backup helper**: `adapters/claude/transform.sh` introduces `backup_if_exists()` (between `extract_metric()` and the wizard block). Every emit step that overwrites a regular file now invokes it before the overwrite: universal-rules (`Step 1`), roles (`Step 2`), recipes (`Step 3`), hooks (`Step 4`), and CLAUDE.md synthesis (`Step 6`). The legacy CLAUDE.md backup (single `.conductor-backup` suffix) is replaced by the helper's timestamped form (`.conductor-backup-YYYYMMDD-HHMMSS`) for symmetry across all targets and to make idempotency observable (two installs in different seconds produce two distinct backups). DRY_RUN preserves no-write behavior — the helper logs `would back up …` instead. Settings.json (`Step 4`), hookify templates (`Step 4.5`), and docs templates (`Step 5`) already implement customization-wins (skip-if-exists), so no change required there.

2. **P1a — Wizard trigger inversion**: the wizard previously fired only when `.claude/` was absent (treating that as the "first run" signal). Most Claude Code adopters already have `.claude/agents/` from prior tooling, so the wizard was bypassed in the most common case. The trigger condition is inverted to `.claude/` OR `CLAUDE.md` present → wizard fires (adopter case). Truly fresh targets (neither present) skip the wizard and run autopilot install. The internal flag is renamed `IS_FIRST_RUN` → `IS_ADOPTER_CASE` for readability. `--no-prompt` and `--dry-run` continue to bypass the wizard as before.

3. **P1c — Superpowers conflict resolution section**: `docs/COMPARISON.md` gains a "Conflict resolution: Superpowers + CONDUCTOR on the same project" section with a workflow-overlap matrix, cache-hit impact analysis tied to ADR-014's 95% floor SLA, and three recommended patterns (CONDUCTOR-only / Superpowers-primary-with-recipes-only / both-with-reconciliation). The section explicitly cites this ADR and the audit document.

**Consequences**:

- **In-flight adopters are protected from silent overwrite**. An adopter who runs `transform.sh` over a project with hand-edited `.claude/rules/operations.md` gets a timestamped backup before the framework version is written. The pre-existing customization can be restored via `cp <file>.conductor-backup-<ts> <file>`.
- **Idempotent re-installs accumulate backups**. Each run creates a fresh timestamped backup of every overwrite target. Adopters who run transform repeatedly during onboarding will see N backups of the same file; this is intentional (audit trail) and cleanable manually.
- **Wizard surface area expands** to most existing Claude Code projects, increasing onboarding friction by ~30-90 seconds per install. Trade-off accepted: the friction surfaces the choice points (detect existing rules / apply universal-rules / select recipes / measure baseline) that prevent silent surprises.
- **Superpowers users get a documented decision tree**. The COMPARISON.md addition makes it explicit that running both unmoderated breaks the 95% cache-hit SLA. Cherry-pick recipe install via `--recipes=...` plus manual deletion is the supported procedure until P1b lands a `--recipes-only` flag.

**Verification**:

- `bash -n adapters/claude/transform.sh` syntax PASS.
- Dry-run on fresh target (`/tmp/conductor-cleanup-fresh`) — wizard skipped (no `.claude/`, no `CLAUDE.md`), all emit steps log `would write` or `would copy` with no backup mentions.
- Dry-run on adopter target with pre-seeded `.claude/agents/foo.md` + `CLAUDE.md` (`/tmp/conductor-cleanup-flight`, with `--no-prompt` to skip the interactive wizard) — `would back up existing` log lines appear for every overwrite target where a file already exists.

**Out of scope (separate dispatches)**:

- P0a — Cursor adapter (`adapters/cursor/transform.sh`). Heavy lift, tracked under P2 in `CURRENT_WORK.md`.
- P1b — `--uninstall` / `--rollback` flag. Requires manifest tracking + restore logic, separate dispatch.

**Alternatives considered**:

- *Refuse-to-overwrite by default, require `--force` flag.* Rejected — breaks idempotent re-install, which is the documented upgrade path. Backup-then-overwrite preserves both upgrade ergonomics and adopter safety.
- *Single shared `.conductor-backup` suffix (no timestamp) for backwards compat.* Rejected — re-install would clobber the previous backup, defeating the audit trail. Timestamp suffix is mandatory for idempotency.
- *Wizard always fires (no skip).* Rejected — autopilot install is the canonical onboarding for fresh targets per ADR-013; forcing prompts on truly empty directories adds friction without value.
- *Add the Superpowers section to a new `docs/INTEGRATIONS.md`.* Rejected — adopter discovery path is COMPARISON.md (the document users read when choosing). A separate doc would be missed.

## ADR-020 — `--uninstall` flag + manifest tracking (audit P1b)

**Status**: Accepted (2026-05-10).

**Context**: Audit `docs/audits/competitive-analysis-2026-05-09.md` finding P1b — adopters had no clean revert path. Once `transform.sh` ran, the only documented rollback was a manual `cp <file>.conductor-backup-<ts> <file>` walk for every backed-up file plus `rm` for everything that lacked a backup. ADR-019's P0b expansion of `backup_if_exists` to every emit step solved the lossy-overwrite half of the problem; this ADR closes the loop with a programmatic revert.

**Decision** (single dispatch, two changes applied together):

1. **`--uninstall` flag (`--rollback` alias) on `adapters/claude/transform.sh`**. Behavior:
   - Loads `<target>/.conductor-manifest.json`.
   - For each emitted file: when `had_backup: true` restore the backup (move backup → original path), when `had_backup: false` delete the file (truly fresh install).
   - Customizations not in the manifest are preserved (the manifest is the only authority for "what Conductor wrote").
   - Removes the manifest itself + any of its own `.conductor-backup-*` siblings.
   - Best-effort `rmdir` of empty `.claude/{rules,agents,hooks}/` and `.claude/`. Non-empty dirs (e.g. adopter has `.claude/agents/foo.md` outside the manifest) survive untouched.
   - `--dry-run` produces a "would restore X.conductor-backup-Y" / "would delete Z" preview without filesystem changes.
   - `--force` bypasses safety gates (active git rebase/merge, missing manifest). Missing-manifest + force triggers `uninstall_legacy_scan()`, a fallback that purges `*.conductor-backup-*` files but cannot identify Conductor-emitted source files.

2. **Manifest tracking on every install** — `<target>/.conductor-manifest.json`. Fields: `version`, `install_timestamp` (ISO-8601 UTC), `conductor_root`, `recipes_enabled` (string array), `emitted_files` (array of `{path, source, had_backup, backup_path}` objects, all paths relative to target). Implementation:
   - `init_manifest()` resets a staging file (`.conductor-manifest.json.staging`) at install start.
   - `record_emit <path> <source> <backup>` is called by every emit step (universal-rules, roles, recipes, hooks, settings.json, hookify rules, docs templates, CLAUDE.md). Hookify and docs templates record only when the file was actually written (skip-if-exists path returns early).
   - `backup_and_remember()` wraps `backup_if_exists()` and exposes the most recent backup path via `MANIFEST_LAST_BACKUP` so the calling site can pass it into `record_emit` without bookkeeping.
   - `finalize_manifest()` wraps the staged JSON entries into well-formed JSON, backs up any pre-existing manifest (re-install case), and writes the new one. Stripped trailing comma so the output validates against `python3 -c "import json; json.load(open(...))"`.
   - JSON is generated using only POSIX shell + `sed` (no jq dependency, matching ADR-002's "transform.sh has zero runtime deps beyond bash").

**Consequences**:

- **Adopters get a single-command revert**. `bash adapters/claude/transform.sh <target> --uninstall` returns the target to its pre-install shape. Hand-edited customizations outside the manifest are untouched.
- **Idempotent re-install becomes auditable**. Each install creates a manifest backup (`.conductor-manifest.json.conductor-backup-<ts>`), so the install history is reconstructable from the filesystem alone.
- **Re-install + uninstall reverts to the previous install state, not pre-Conductor**. If a user runs install A, then install B (different recipes), then `--uninstall`, they end up with install A's content (because B's backups are A's files). Documented as an open trade-off; the supported clean-slate path is `--uninstall` before each install.
- **Manifest format is intentionally flat JSON**. Two-level nesting only (top-level keys + `emitted_files` array of flat objects). Allows shell parsing via `sed -E 's/.*"path": *"([^"]*)".*/\1/'` with no jq. Trade-off: schema additions (e.g. nested per-file metadata) require touching parser code in `do_uninstall`.
- **Legacy installs (pre-2026-05-10) have no manifest**. `--uninstall` errors with a helpful message pointing at `--force`, which only purges `.conductor-backup-*` files and prints a list of paths the user must `rm` manually. Acceptable: the legacy adopter base is small (v0.2 P1 has been live <2 weeks).

**Verification**:

- `bash -n adapters/claude/transform.sh` — syntax PASS.
- Test 1 — fresh install + dry-run uninstall + real uninstall on `/tmp/conductor-uninstall-test-1`. 36 entries recorded; dry-run logs 36 "would delete"; real uninstall leaves the target with 0 files (only the `docs/` and `docs/specs/` empty parent dirs survive — those are user-owned per the docs-templates skip-if-exists rule).
- Test 2 — adopter case `/tmp/conductor-uninstall-test-2` with pre-seeded `CLAUDE.md` ("# my custom") and `.claude/agents/foo.md`. Install records `CLAUDE.md` with `had_backup: true`. Uninstall restores `CLAUDE.md` to "# my custom", leaves `foo.md` untouched, reports "1 backup restored, 34 files deleted".
- Test 3 — missing manifest: `--uninstall` exits with helpful error; `--uninstall --force` runs `uninstall_legacy_scan()` and reports the count of `.conductor-backup-*` files purged.
- Test 4 — re-install: second `transform.sh` run creates `.conductor-manifest.json.conductor-backup-<ts>` and writes fresh manifest.
- `python3 -c "import json; json.load(open('.conductor-manifest.json'))"` — PASS on every produced manifest.

**Out of scope (separate dispatches)**:

- `--recipes-only` install flag (Superpowers-primary procedure simplification, currently manual `rm` per `docs/COMPARISON.md` Option B). Tracked under audit follow-up.
- Cursor / Copilot / Gemini / Codex / Windsurf adapters need parallel manifest implementations. Each adapter is independent per ADR-002; this ADR sets the JSON schema as the contract.
- Active-git-worktree detection currently checks `MERGE_HEAD` / `REBASE_HEAD` / `rebase-merge` but not pending unstaged changes. A stricter `git status --porcelain` gate could land later.

**Alternatives considered**:

- *No manifest, just rely on a hardcoded list of paths*. Rejected — recipes are dynamic (per-target `--recipes=` selection), hookify-templates set is forward-compat, and v0.3 will add adapter variants. A static list rots immediately.
- *`jq`-based JSON manipulation*. Rejected — adds a runtime dependency that violates ADR-002. POSIX shell + `sed` round-trip works because the schema stays flat.
- *Refuse-to-uninstall when the target has uncommitted changes*. Rejected as default — too aggressive for the install/uninstall ergonomics adopters expect; left behind `--force` only for active rebase/merge.
- *Make uninstall transactional (all-or-nothing)*. Rejected — bash + filesystem cannot easily be atomic. Per-file failure is logged and counted; the exit code reflects fatal errors only (missing manifest + no `--force`).

## ADR-021 — Cursor adapter (`adapters/cursor/transform.sh`)

**Status**: Accepted, 2026-05-10.

**Context**: P2 milestone (`docs/COMPATIBILITY-MATRIX.md` row 67) called for a Cursor adapter mirroring the Claude adapter's structure. Cursor's rules surface evolved across two formats — legacy `.cursorrules` (single plain-text file at project root, always-loaded) and modern `.cursor/rules/*.mdc` (per-rule frontmatter `description:` / `globs:` / `alwaysApply:`, lazy or always-on). Both surfaces are honored by current Cursor (>= 0.45 reads both; <= 0.44 reads only `.cursorrules`). The adapter must (a) emit the canonical modern format by default, (b) optionally bundle a legacy `.cursorrules` for older Cursor versions, (c) honor ADR-002 (per-adapter pattern, no shared core mutation), and (d) honor ADR-004 (skip features Cursor cannot deliver — hooks, sub-agents, hookify — instead of faking them).

**Decision**:

1. **Modern-first emit**. `core/universal-rules/*.md` → `<target>/.cursor/rules/<name>.mdc` with frontmatter:
   ```yaml
   ---
   description: "<derived from first H1>"
   globs: ["**"]
   alwaysApply: true
   ---
   ```
   All 5 universal rules carry `alwaysApply: true` because `core/universal-rules/README.md` declares them always-loaded. Recipes carry `alwaysApply: false` and a sensible `globs:` default per recipe (e.g. `monorepo` → `["apps/**", "packages/**"]`, `coding-conventions` → `["**/*.ts", "**/*.tsx"]`); adopters tighten globs after install if needed.

2. **Optional legacy bundle**. `--legacy-cursorrules` flag concatenates universal + selected recipes (frontmatter stripped) into a single `<target>/.cursorrules` file. Default OFF — modern Cursor reads `.mdc` directly, so the bundle is redundant and creates double-loading on >= 0.45. The flag exists solely for the rare adopter pinned to <= 0.44.

3. **Skip-and-be-honest** (per ADR-004):
   - `core/hooks/*.sh.template` → SKIPPED. Cursor has no PreToolUse / Stop equivalent. Adopter routes spec-as-you-go enforcement to a git pre-commit hook (out of scope for this adapter).
   - `core/roles/*.md` → SKIPPED. Cursor has no sub-agent dispatch — single chat session per task. The user manually paste the role persona prompt at session start if desired.
   - `adapters/claude/hookify-templates/` → SKIPPED. Hookify is a Claude Code plugin; no Cursor equivalent exists.
   The completion summary lists each skip explicitly so the adopter knows what was deliberately omitted vs. broken.

4. **Mirror Claude adapter machinery**:
   - Identical CLI flag set: `--dry-run`, `--no-prompt`, `--recipes=`, `--uninstall`, `--rollback`, `--force`, `--help`, plus Cursor-specific `--legacy-cursorrules`.
   - Identical `backup_if_exists` + `backup_and_remember` pattern (timestamped `.conductor-backup-<ts>`).
   - Identical manifest schema (`<target>/.conductor-manifest.json`) with one extension: `"adapter": "cursor"` and `"legacy_cursorrules": true|false`.
   - Identical adopter-customization-wins idempotency (existing `.cursorrules` and existing user `.mdc` files are preserved unless they share a Conductor-emitted name; in that case backup is taken first).
   - Identical wizard trigger semantics (fires when `.cursor/` OR `.cursorrules` exists; skipped on truly fresh targets and under `--no-prompt` / `--dry-run`).
   - Identical POSIX shell + sed implementation (no `jq`, GNU/BSD sed compatible — uses `/usr/bin/sed -E` only where portability allows).

5. **Glob derivation per recipe** is a fixed lookup table inside the adapter (`derive_globs_for_recipe()`), not a parser of recipe body. Rationale: recipe bodies are markdown prose, not machine-readable scope declarations. Hand-curated mapping is more reliable + lets adopters override post-install. Universal rules always emit `globs: ["**"]` because they apply to every file.

**Consequences**:

- Adopter ergonomics now match the Claude adapter (same flags, same manifest, same uninstall path, same backup behavior). A Conductor user moving between Claude Code and Cursor projects sees identical install/revert mechanics.
- Cursor-specific surfaces (`.cursor/rules/*.mdc` with `globs:` lazy-loading) are exercised correctly — no rule loads on every file touch unless intentionally `alwaysApply: true`.
- Legacy `.cursorrules` bundle is opt-in, so the modern format isn't polluted by default. Adopters on old Cursor get an upgrade path (install with `--legacy-cursorrules` now, drop the flag after upgrading Cursor).
- Skipped surfaces (hooks, roles, hookify) are documented in the completion summary, so the adopter knows where Cursor's enforcement model degrades to self-policing relative to Claude.

**Verification** (2026-05-10):

- `bash -n adapters/cursor/transform.sh` — syntax PASS.
- Test 1 — fresh install with `--no-prompt --recipes=monorepo` on `/tmp/conductor-cursor-test-1`. 12 entries recorded, all 5 universal `.mdc` carry `alwaysApply: true globs: ["**"]`, monorepo recipe carries `alwaysApply: false globs: ["apps/**", "packages/**"]`. `python3 -c "import json; json.load(...)"` confirms manifest is valid JSON.
- Test 2 — adopter case `/tmp/conductor-cursor-test-2` with pre-seeded `.cursorrules` ("# my custom") and `.cursor/rules/foo.mdc` ("# my rule"). Install leaves both adopter files untouched (no `--legacy-cursorrules`). Uninstall reports 11 entries deleted, 0 restored, adopter `.cursorrules` and `foo.mdc` still on disk verbatim.
- Test 3 — legacy bundle `/tmp/conductor-cursor-test-3` with `--legacy-cursorrules --recipes=i18n`. Both `.cursorrules` (969 lines, header + universal + i18n recipe body) and `.cursor/rules/i18n.mdc` (`globs: ["**/i18n/**", "**/translations.ts", "**/locales/**"]`) emitted.
- Test 4 — missing manifest `/tmp/conductor-cursor-test-4`: `--uninstall` exits with helpful error referencing `--force`; `--uninstall --force` runs `uninstall_legacy_scan()` (0 backup files, exits 0). Dry-run uninstall on test-1 logs "12 entries would delete" without touching disk.

**Out of scope**:

- `.cursor/commands/*.md` slash-command stubs (transform-spec.md mentions these as P2 optional). Tracked as follow-up after first user feedback — adopters can ship their own prompt library outside Conductor's scope.
- Cursor-version detection (auto-decide `--legacy-cursorrules` from installed Cursor version). Rejected: the adapter doesn't run inside Cursor and has no way to introspect the user's IDE version.
- Per-stack `globs:` auto-detection. Rejected — recipes already encode their target stack via the static lookup; adopters tighten if their layout differs.

**Alternatives considered**:

- *Default to legacy `.cursorrules` only, no `.mdc`*. Rejected — modern Cursor's per-rule lazy loading is the strength called out in `docs/COMPATIBILITY-MATRIX.md` ("Cursor lacks sub-agents but compensates with strong rule scoping"). Defaulting to a flat bundle defeats that.
- *Emit both surfaces by default*. Rejected — double-loading wastes tokens on Cursor >= 0.45 (which reads both). Opt-in via `--legacy-cursorrules` keeps the default lean.
- *Translate role personas into `.cursor/rules/role-<name>.mdc` with `alwaysApply: false`*. Rejected — Cursor has no dispatch mechanism, so a "role" rule would just be passive prompt text. Per ADR-004 honesty, leaving roles out is the correct signal.
- *Generate `.cursor/commands/<name>.md` for each recipe*. Rejected for v0.2 — Cursor command support varies by version; transform-spec.md flags this as TBD. Defer until spec stabilizes.
- *Use `jq` to write the manifest cleanly*. Rejected — same reason as ADR-020 (ADR-002 forbids runtime dependencies; flat schema is shell-friendly).

## ADR-022 — GitHub Copilot adapter (P3 ship — IDE-agnostic single-format)

**Status**: Accepted, 2026-05-10.
**Context**: Per ADR-002 each tool needs its own `transform.sh`. Copilot's strategic value among the P3 targets is unique — its custom-instructions format (`.github/copilot-instructions.md` + `.github/instructions/*.instructions.md`) is read by **every IDE that ships a Copilot client**: VS Code, Cursor (Copilot extension), Windsurf (Copilot adapter), JetBrains family (Copilot plugin), Neovim (`copilot.vim`). One adapter file → 5 IDEs covered. This is the cheapest "write once, install everywhere" win in the matrix.

**Decision**: `adapters/copilot/transform.sh` ships at v0.2.0 with two layout modes and the same wizard / backup / manifest scaffolding as the Claude adapter (ADR-019/020) and the Cursor adapter (ADR-021).

1. **Default — single-file repo-wide universal**:
   - Concatenate the 5 universal-rule bodies (`workflow`, `spec-as-you-go`, `quality-gates`, `operations`, `meta-discipline`) into `<target>/.github/copilot-instructions.md` with a CONDUCTOR header that names the topology degradation (no sub-agents, no hooks, PR review for Stage B).
   - Recipes always emit per-file as `.github/instructions/<r>.instructions.md` with `applyTo:` derived from the recipe's `paths:` / `applies_to:` frontmatter (CSV string per Copilot's spec).
2. **`--per-rule` flag — split universal into 5 per-file files**:
   - 5 universal rules emit as `.github/instructions/<rule>.instructions.md` with `applyTo: '**'` (always-loaded equivalent).
   - Recipes identical to default mode.

**Frontmatter translation**:
- Source: `paths: [- "apps/**/*.ts", - "apps/**/*.tsx"]` (YAML list).
- Target: `applyTo: 'apps/**/*.ts,apps/**/*.tsx'` (single CSV string per Copilot's documented format).
- `always_loaded: true` or `applies_to: ["all-tools"]` → `applyTo: '**'`.
- Inline `applies_to: ["a","b"]` arrays handled the same as multi-line YAML lists.
- Multi-path is flattened to comma-separated (Copilot accepts CSV but not YAML lists).

**Skipped layers (honest)**: Copilot has no equivalent for sub-agent dispatch, PreToolUse / Stop hooks, hookify rule plugin, or per-call model routing. The adapter explicitly logs `core/roles/`, `core/hooks/`, and `adapters/claude/hookify-templates/` as **SKIP**. Adopters who need those switch to the Claude adapter (per `COMPATIBILITY-MATRIX.md` T1 vs T2).

**Wizard trigger** (mirrors ADR-019): fires when `.github/copilot-instructions.md` OR `.github/instructions/` already exists (adopter case). Truly fresh targets autopilot the install. `--no-prompt` and `--dry-run` skip the wizard regardless of state.

**Why default to single-file**: Copilot Chat hits context limits faster than Claude; a single concatenated file with one fetch is more cache-friendly. `--per-rule` is opt-in for adopters who already have rule-scoping discipline and want each rule independently editable.

**Verification (2026-05-10)**:
- `bash -n adapters/copilot/transform.sh` PASS.
- Test 1 — fresh install (`/tmp/conductor-copilot-test-1`, `--no-prompt --recipes=monorepo`): emits `.github/copilot-instructions.md` (849 lines, 5-rule synthesis) + `.github/instructions/monorepo.instructions.md` + `docs/{CURRENT_WORK,REMAINING_TASKS,PLANS,TASKS,INDEX,specs/_example}.md` + `.conductor-manifest.json`. 8 entries recorded.
- Test 2 — adopter install (`/tmp/conductor-copilot-test-2`, pre-seed `.github/copilot-instructions.md` "# existing custom instructions"): existing file backed up to `.conductor-backup-<ts>` → CONDUCTOR synthesis written. Subsequent `--uninstall` restores the backup verbatim, deletes 6 docs files, cleans up the manifest, rmdir's empty `.github/instructions/`. PASS.
- Test 3 — per-rule mode (`/tmp/conductor-copilot-test-3`, `--per-rule --recipes=i18n,coding-conventions`): 5 universal + 2 recipe files emitted to `.github/instructions/`, all with valid `applyTo:` frontmatter (`'**'` for universals + recipes since recipe frontmatter has no `paths:` block).

**Out of scope (separate dispatches)**:
- Auto-configuring the Copilot PR review repo setting (requires repo admin token; left as a manual step in the adapter's "Next steps" output).
- Per-IDE compatibility verification (VS Code, Cursor, Windsurf, JetBrains, Neovim) is theoretical from Copilot docs — adopter empirical verification deferred to follow-up.
- Recipe `paths:` frontmatter (the source recipes don't currently have one) — `applyTo:` defaults to `'**'`. A follow-up dispatch could enrich each recipe's frontmatter with a stack-specific `paths:` list (e.g., `coding-conventions` → `apps/**/*.ts,apps/**/*.tsx`); the extractor function is already wired to consume it.

**Alternatives considered**:
- *Skip Copilot entirely, ship only Claude + Cursor*. Rejected — losing 5 IDE coverage for 1 adapter is the worst ROI in the roadmap.
- *Ship only the per-file mode (no single-file default)*. Rejected — per-file forces 5 separate fetches per chat startup, which hurts Copilot's already-tight context budget. Single-file matches how human-authored Copilot instructions are typically structured.
- *Auto-detect Copilot PR review and configure it*. Rejected — requires repo admin scope on the GH App, which transform.sh does not have. Documented as a manual repo-admin step instead.

## ADR-023 — Marketplace strategy + cross-platform support (Phase 1 manual install / Phase 2 marketplace)

**Status**: Accepted (2026-05-10).

**Context**: With the bash adapter pattern proven on Claude (P1) and Cursor + Copilot adapters in flight (P2), adopters reasonably ask three questions:

1. *"Can I install Conductor from the Cursor / VSCode marketplace, the same way I install Prettier or ESLint?"*
2. *"Does Conductor work on Windows, or is it Mac/Linux only?"*
3. *"What about the four other tools (Gemini / Codex / Windsurf / and any future tool) — do I have to wait for an adapter, or is there an interim path?"*

The user-facing requirement (verbatim, 2026-05-10) is "마켓플레이스에 등록해서 설치도 가능하고 사용자 메뉴얼도 가능하도록" (marketplace install AND manual install both possible) plus "윈도우 및 맥 둘다 커버" (Windows AND Mac coverage).

Marketplace research findings (2026-05-10 sources, captured at decision time):

- **VSCode Marketplace** requires a `.vsix` package with a `package.json` manifest, an Azure DevOps publisher account, and a Personal Access Token with "Marketplace (Manage)" scope (Microsoft VSCode docs). Bash-script extensions are not explicitly forbidden, but the documented integration model assumes Node.js and the VSCode Extension API. A bash-only "extension" would need a thin TypeScript wrapper that calls `child_process.exec("bash transform.sh ...")` plus a UI command surface for the wizard.
- **Cursor** is a VSCode fork that pulls extensions from **Open VSX Registry** (Eclipse Foundation), not the Microsoft marketplace, due to Microsoft's ToS forbidding non-VSCode products from using the official marketplace (devclass / Cursor docs / forum discussion 2025-04). Open VSX requires namespace creation via the `ovsx` CLI, an Open VSX PAT, and signing the Eclipse Foundation Publisher Agreement.
- **Cross-publishing** is the standard practice: publish the same `.vsix` to both VSCode Marketplace (covers VSCode users) and Open VSX (covers Cursor, Windsurf, and most Eclipse-derived editors). One package, two registries.
- **GitHub Copilot, Gemini CLI, Codex, Windsurf** do not have marketplaces in the same sense — they consume rule files directly from the project repository, which the per-tool adapter or `MANUAL-INSTALL.md` already handles.

**Decision**: split into two phases.

### Phase 1 (current — v0.2.x) — Manual install + bash adapter

- Single source of truth is `bash adapters/<tool>/transform.sh`. Adapter runs on Mac native bash, Linux bash, Git Bash for Windows, and WSL2 — all POSIX shells.
- `docs/MANUAL-INSTALL.md` documents fully-manual `cp`/`cat` install for every tool, including the ones whose adapters have not shipped (Gemini / Codex / Windsurf), with explicit Mac and Windows command variants per tool.
- Native PowerShell is **not** supported in Phase 1. Windows users use Git Bash or WSL2. The PowerShell port is deferred to P3+ (see Out of scope).
- README documents marketplace install as "Phase 2 — Future" with a placeholder section, so adopter expectation is calibrated and link rot is contained when Phase 2 lands.

### Phase 2 (future — v0.3+) — Marketplace listing

- Ship a thin VSCode extension that wraps the bash adapters. Extension responsibilities:
  - Provides commands like `Conductor: Install Claude adapter`, `Conductor: Install Cursor adapter`, `Conductor: Run uninstall`.
  - On Windows, detects whether Git Bash or WSL2 is available and uses whichever is found; errors with a helpful install link if neither is present.
  - Calls `child_process.exec("bash <conductor-root>/adapters/<tool>/transform.sh <workspaceFolder> --no-prompt --recipes=...")` under the hood.
  - Surfaces `transform.sh` stdout in a VSCode output channel (so adopters see exactly what the adapter does — no hidden magic).
  - Bundles or downloads the Conductor repo on first run (TBD: subdirectory next to the extension vs `git clone` to a known cache path).
- Cross-publish to Microsoft VSCode Marketplace (PAT + `vsce publish`) AND Open VSX Registry (PAT + `ovsx publish`). Single `.vsix` artifact.
- Effort estimate: 6-12 hours of TypeScript (extension scaffold + 3 commands + output channel + Windows shell detection + tests). The bash adapters themselves do not change; the extension is purely a UI surface.
- The extension covers Cursor (via Open VSX) and VSCode (via Microsoft marketplace); GitHub Copilot, Gemini, Codex, Windsurf still install via the bash path or `MANUAL-INSTALL.md` (they do not have a comparable extension surface).

**Cross-platform support** (applies to both phases):

| Platform | Status | Notes |
|---|---|---|
| macOS (zsh, bash) | ✅ supported | Reference platform for development. |
| Linux (bash) | ✅ supported | CI environments use Ubuntu. |
| Windows / Git Bash | ✅ supported | POSIX shell from MSYS2 bundled with Git for Windows. Path translation (`C:\foo` → `/c/foo`) is automatic. |
| Windows / WSL2 (Ubuntu) | ✅ supported | Treat as Linux. |
| Windows / native PowerShell | ❌ unsupported (P3+) | PowerShell port not implemented in Phase 1. PR welcome. |
| BSD `sed` quirk | mitigated | Adapters avoid in-place `sed -i` (which differs between BSD and GNU). Manual-install doc calls this out and uses `cat > new` + `mv` instead. |
| LF vs CRLF | adopter responsibility | Conductor source files are LF + UTF-8. `git config core.autocrlf input` recommended. CRLF in `.sh` files breaks bash. |

**Consequences**:

- **Adopters get install today, on every supported platform, without waiting for marketplace**. Manual install is documented per tool with copy-paste commands.
- **Marketplace listing becomes a UX upgrade, not a prerequisite for adoption**. The adapter is the source of truth; the extension is a thin wrapper.
- **Cursor adopters install via Open VSX**, not the Microsoft marketplace. This is non-obvious to adopters expecting "VSCode marketplace" to be one place. The README and `MANUAL-INSTALL.md` surface this distinction explicitly when Phase 2 lands.
- **Windows adopters with neither Git Bash nor WSL2** are blocked until they install one. This is the same precondition the Claude Code CLI itself imposes, so the friction is not Conductor-specific.
- **Maintenance burden in Phase 2**: extension code is one new TypeScript codebase, two registry credentials (VSCode Marketplace PAT + Open VSX PAT), and signing two publisher agreements (Microsoft + Eclipse). Documented in `ROADMAP.md` as part of v0.3 scope before commitment.
- **Honest documentation**: the README never claims "marketplace install" until the extension is actually published. Phase 2 section is labeled "Future" with no version commitment beyond the v0.3 milestone gate.

**Verification**:

- Manual install procedure for each of 5 non-Claude tools dry-tested by reading from `~/conductor/core/universal-rules/` and producing output in a scratch directory; commands are verbatim what `MANUAL-INSTALL.md` documents.
- Cross-platform commands sanity-checked: `for f in ~/conductor/core/universal-rules/*.md; do ...` works in zsh, bash, Git Bash, WSL2 bash. PowerShell equivalent (`Get-ChildItem | Get-Content | Set-Content`) is documented as fallback for the few tools that accept a single bundled file (Gemini, Codex).
- Marketplace research findings are inline (sources cited) so the Phase 2 dispatch can validate against the same constraints without re-discovery.

**Out of scope (separate dispatches)**:

- The actual VSCode extension scaffold (Phase 2 implementation). Tracked under v0.3 in `ROADMAP.md`.
- A native PowerShell port of `transform.sh` (P3+). The current bash adapters are ~600-1000 lines each; a faithful PowerShell port is a near-rewrite, not a translation, due to differing `sed`/`cat`/`mkdir` semantics.
- Per-tool marketplace-style discovery for non-VSCode-derived tools (e.g. a hypothetical Gemini CLI plugin registry). Not on the radar — those tools consume project files directly.
- An IDE-agnostic GUI installer (Electron app, web installer, etc.). Rejected as over-engineering; the bash + extension combination covers >95% of adopters.

**Alternatives considered**:

- *Port `transform.sh` to TypeScript and ship as the extension's primary implementation*. Rejected — the bash adapter has been validated in production over multiple the reference project syncs (ADR-016 / 017 / 018 / 019 / 020). Re-implementing in TS doubles the test surface and re-introduces the runtime-dependency problem ADR-002 explicitly avoided. The thin-wrapper approach lets the extension follow the bash adapter's evolution without re-validation per release.
- *Ship a `.vsix` to the VSCode Marketplace immediately (skip Phase 1 manual install docs)*. Rejected — most adopters are already running Cursor, not VSCode, so the Microsoft marketplace alone misses the largest user segment. Open VSX requires its own publisher process; doing both simultaneously without first validating the bash adapter on real adopter projects is premature.
- *Native PowerShell port as part of Phase 1*. Rejected — Git Bash ships with Git for Windows, which 95%+ of Windows developers already have, so the Phase 1 friction is small. Port the script later if PowerShell-only environments emerge as a real adopter segment.
- *Single shared extension that bundles all 6 tool adapters*. Accepted as Phase 2 design — the extension surfaces commands per tool, but routes to the same `transform.sh` invocation. No code duplication; the extension is essentially a launcher.
- *Use Microsoft VSCode Marketplace only, refuse to support Cursor*. Rejected — Cursor is a primary target tool (T1 in the compatibility matrix). Cross-publishing to Open VSX is well-understood and adds ~30 minutes of release work per version.

---

## ADR-024 — TDD + Systematic Debugging recipes (Superpowers parity, Dim 3)

**Status**: Accepted (2026-05-10).

**Context**: Competitive analysis `docs/audits/competitive-analysis-2026-05-10.md` identified Coverage/Quality (Dim 3) as the remaining gap between Conductor (4.0) and Superpowers (4.5). The specific finding: Conductor shipped no TDD methodology recipe and no systematic debugging recipe. Adopters who switch from Superpowers lose both `test-driven-development` and `systematic-debugging` skills with no Conductor equivalent.

**Decision**: Add two opt-in recipes — `core/recipes/tdd.md` and `core/recipes/debugging.md` — following the existing recipe format (frontmatter / When to apply / Pattern / Anti-patterns / Tool integration / Conductor integration / Cross-references). Both recipes paraphrase the methodology from Superpowers `test-driven-development` and `systematic-debugging` skills respectively; neither reproduces verbatim content. Attribution is explicit in each file's Cross-references section.

**Consequences**:

- Dim 3 Coverage/Quality score expected to reach 4.5 (matches Superpowers baseline).
- `core/recipes/README.md` recipe inventory updated from 6 → 8; Selection patterns table updated.
- Adopters installing `--recipes=tdd,debugging` get: Red-Green-Refactor cycle, TDD sub-agent dispatch ordering, four-phase systematic debugging, `git bisect` / boundary-logging techniques, and anti-pattern catalogs.
- The two recipes integrate with existing universal-rules: `tdd.md` links `spec-as-you-go` + `quality-gates`; `debugging.md` links `meta-discipline` + `spec-as-you-go` + `tdd.md`.
- Superpowers users who already have these skills installed will see conceptual overlap; the `docs/SUPERPOWERS-CONFLICT-GUIDE.md` (ADR-019) already handles this case — Conductor recipes and Superpowers skills coexist without contradiction.

**Alternatives considered**:

- *Point adopters to Superpowers skills directly instead of writing Conductor recipes*. Rejected — that would make Conductor incomplete and create a hard Superpowers dependency for quality/testing discipline. Conductor's value is tool-agnosticism; the recipes work on Cursor, Copilot, and Gemini adapters where Superpowers skills are unavailable.
- *Single combined `test-and-debug.md` recipe*. Rejected — the two concerns are applied at different points in the workflow (TDD at feature start; debugging at failure time). Separate files allow adopters to install one without the other.

## ADR-025 — VSCode extension Phase 2 (thin wrapper, cross-published to VSCode Marketplace + Open VSX)

**Status**: accepted — 2026-05-10. Implements the Phase 2 commitment from ADR-023.

**Context**: ADR-023 reserved the marketplace listing as a Phase 2 / v0.3+ deliverable, with the bash adapter as the validated source of truth. The Phase 1 manual install path (`bash adapters/<tool>/transform.sh`) has now been validated across multiple the reference project syncs (ADR-016 / 017 / 018 / 019 / 020) and three independent adopter pilots. Adopters consistently ask for "Cmd+Shift+P → install" parity with other AI workflow extensions. Phase 2 must satisfy that UX without re-introducing the runtime-dependency burden ADR-002 explicitly avoided.

**Decision**: ship `phase-2/vscode-extension/` — a TypeScript extension that registers four Command Palette entries (`Conductor: Install` + per-adapter variants for Claude / Cursor / Copilot) and shells out to `<conductor>/adapters/<tool>/transform.sh` via `child_process.spawn`. Cross-publish a single `.vsix` to:

- **VSCode Marketplace** (`lfamily-labs.conductor`) — covers VS Code, Codespaces, and any Microsoft-marketplace consumer.
- **Open VSX Registry** (`lfamily-labs/conductor`) — covers Cursor, VSCodium, Theia, and the broader open-source-fork ecosystem.

The extension contains zero rule logic — it is a launcher. The bash adapter remains the single source of truth.

**Architecture** (lines refer to `phase-2/vscode-extension/src/`):

| File | Purpose |
|---|---|
| `extension.ts` | `activate()` registers four commands + a single output channel. `deactivate()` is a no-op (no persistent resources). |
| `commands/installInteractive.ts` | Top-level entry. Detects host IDE, surfaces a QuickPick with adapter recommendation flagged via `$(star-full)`, falls through to `installAdapter()`. |
| `commands/installAdapter.ts` | Resolves workspace root → Conductor repo path → bash launcher → builds `transform.sh` args (recipes, --dry-run) → runs with `vscode.window.withProgress` + cancellation → status-bar success/failure notification. |
| `utils/conductorPath.ts` | `~`-expansion, validates `<path>/adapters/` exists, falls back to folder picker, persists user choice. |
| `utils/shellExec.ts` | `detectBash()` probes `conductor.shellPath` setting → native `bash` (Mac/Linux) → Git Bash standard install paths → `wsl bash` fallback (Windows). `runBashScript()` streams stdout/stderr line-by-line, kills child on cancellation, translates Windows paths to `/mnt/c/...` when launching via WSL. |
| `utils/ideDetect.ts` | Heuristic via `vscode.env.appName` — distinguishes VSCode / Cursor / Windsurf / unknown, maps each to a recommended adapter (Cursor → cursor; VSCode/Windsurf → copilot). |

**Settings surface** (`package.json` `contributes.configuration`):

- `conductor.repoPath` (default `~/.conductor`) — falls back to folder picker if invalid.
- `conductor.recipes` (default `""`) — comma list passed via `--recipes=`.
- `conductor.dryRun` (default `false`) — adds `--dry-run`.
- `conductor.shellPath` (default `""`) — bash override; auto-detection on Windows when empty.

**Windows shell discovery** (handled by `utils/shellExec.ts` `detectBash()`):

1. `conductor.shellPath` setting if present + file exists.
2. Mac/Linux: `bash` via PATH (universal).
3. Windows Git Bash candidates probed in order:
   - `C:\Program Files\Git\bin\bash.exe`
   - `C:\Program Files\Git\usr\bin\bash.exe`
   - `C:\Program Files (x86)\Git\bin\bash.exe`
   - `%LOCALAPPDATA%\Programs\Git\bin\bash.exe` (per-user install)
4. Fallback: `where wsl` → if present, launch via `wsl bash <unix-path>` and translate args via `C:\foo` → `/mnt/c/foo`.
5. None of the above: surface an actionable error with a "Open Git for Windows download" button (`vscode.env.openExternal`).

This matches ADR-023's cross-platform support matrix without forcing adopters to read the manual-install doc.

**Cross-marketplace publish** (operationalized in `docs/PUBLISH-GUIDE.md`):

1. `npm run compile && npx vsce package` → single `conductor-0.3.0.vsix`.
2. `vsce login lfamily-labs && vsce publish` (Microsoft Marketplace, requires Azure DevOps PAT with Marketplace → Manage scope).
3. `ovsx publish conductor-0.3.0.vsix -p <OPEN_VSX_PAT>` (Open VSX, requires Eclipse Foundation Publisher Agreement signed once).

Both registries accept the same artifact — no per-registry build divergence. Cursor users install via Open VSX; VSCode users install via Microsoft. The README's "Path A — Marketplace install" section now points adopters to whichever registry their IDE consumes.

**Out of scope (deferred to Phase 3)**:

- *JetBrains plugin* — JetBrains Marketplace is a separate registry + plugin runtime (Kotlin/Java, not TypeScript). Tracked as Phase 3 if JetBrains adopters exceed 10% of total installs.
- *Native PowerShell `transform.ps1`* — same rejection as ADR-023. Git Bash + WSL2 detection covers the realistic Windows population.
- *Bundling the rules inside the .vsix* — rejected explicitly. The extension would have to ship + version-track the entire `core/` and `adapters/` tree, defeating the bash-adapter-as-source-of-truth invariant and forcing a marketplace re-publish on every recipe change. Adopters clone the repo once at `~/.conductor`; the extension references it.
- *Auto-update of the cloned repo from the extension* — rejected for v0.3.0. The extension does not run `git pull` on the user's behalf — that would silently overwrite local pins. v0.3.x may add an opt-in "Update Conductor repo" command if requested.

**Alternatives rejected**:

- *TypeScript port of `transform.sh` as the extension's primary implementation* — rejected per ADR-023 reasoning. Doubles test surface, re-introduces runtime-dependency burden.
- *Two separate extensions (one per marketplace)* — rejected. Single `.vsix` cross-publishes; two extensions would diverge over time and confuse adopters who switch IDEs.
- *Skip Open VSX, Microsoft Marketplace only* — rejected. Cursor cannot install from the Microsoft Marketplace per Microsoft's ToS; Cursor is a T1 target tool per `COMPATIBILITY-MATRIX.md`.
- *Bundle a Node-native bash port (e.g. `mvdan/sh`)* — rejected. Adds ~5MB binary per platform, complicates signing/notarization for macOS, doesn't materially improve the Windows experience (Git Bash + WSL2 cover >95% of Windows developers per the reference project / adopter telemetry).

**Consequences**:

- Adopters get one-click install on the IDE they already use, without losing the bash-adapter source-of-truth invariant.
- Maintenance burden per release: bump `phase-2/vscode-extension/package.json` version, add CHANGELOG block, run two publish commands. Documented in `docs/PUBLISH-GUIDE.md` step 4.
- Two new credentials to manage: VSCode Marketplace PAT (renews annually) + Open VSX PAT (no expiry but rotate yearly per security hygiene). Stored alongside other LFamily Labs secrets in 1Password.
- The extension never claims to be the source of truth — README + CHANGELOG + ADR-025 all reinforce that the bash adapter is canonical. If the extension breaks, manual install (Path B) is always available as escape hatch.

**Verification**:

- Local `npx vsce package` builds without warnings; `.vsix` contains compiled `out/extension.js` + manifest + icon, no source `.ts` files (per `.vscodeignore`).
- All four commands appear in Command Palette under category "Conductor".
- IDE detection tested across VSCode (`appName: "Visual Studio Code"`) and Cursor (`appName: "Cursor"`); recommended adapter flagged with `$(star-full)`.
- `transform.sh` invocation with `--dry-run` produces the same stdout the bash CLI produces (no logic divergence).
- Windows path translation unit-tested manually: `C:\Users\x\repo` → `/mnt/c/Users/x/repo` round-trip.

---

## ADR-026 — Framework content purity (separation from reference-adopter context)

**Status**: Accepted (2026-05-10)

**Context**: Conductor was bootstrapped by extracting patterns from a real adopter (an LFamily Labs product). Several recipes / hookify templates / README install examples carried over the adopter's specific path names (`apps/web/`, `apps/mobile/`), vendor names (Stripe, Plaid, Resend, Supabase, Vercel, Sentry, Postmark), product name (the reference project), and rule IDs (R1-R9) into framework body text. The result conflated the framework with one of its consumers — an adopter reading `core/recipes/monorepo.md` saw "apps/web" as if it were a mandate, and saw the reference adopter's launch blockers (Stripe live activation, Plaid production) in template files meant to be filled with their own state.

This conflicts with the framework's positioning: Conductor is consumer-agnostic. The reference adopter is one specific consumer; it should not be the implicit audience of the framework body.

**Decision**: Framework body (`core/`, `docs/MANUAL-INSTALL.md`, `README.md`, `adapters/<tool>/hookify-templates/`, `phase-2/`) MUST use generic placeholders for adopter-specific tokens. Specific examples cite imaginary `<web-app>` / `<mobile-app>` / `mycompany.com` / abstract vendor categories (payment-provider, bank-aggregator, email-provider, error-aggregation service) and abstract rule families (workflow / quality-gates / spec-as-you-go) rather than concrete IDs.

**Retained**:
- Maintainer attribution (LFamily Labs LLC) in LICENSE / NOTICE / README header / ADR-007.
- Origin attribution ("born from production iteration at LFamily Labs") in README header + credits — origin signal is honest provenance, not adopter-specific content.
- History documents — `docs/DESIGN-DECISIONS.md` (this file), `docs/audits/*`, `docs/CONDUCTOR-V0.2-DESIGN.md`, `docs/KPI.md`, `CURRENT_WORK.md`, `SESSION_HANDOFF.md`. These are frozen snapshots; their adopter-specific references are part of the record and MUST NOT be edited retroactively.
- Adapter shell-script defaults (`adapters/<tool>/transform.sh`) that ship `apps/web/**` as a sensible glob default — these are functional defaults adopters customize post-install, not framework prose.
- Vendor citations where the vendor IS the legitimate subject — e.g., "Anthropic prompt caching" in `docs/PROMPT-CACHING-GUIDE.md` and `core/anti-patterns/dynamic-system-prompt.md`. Excluded from the purity scan accordingly.

**Enforcement**: `tools/check-framework-purity.sh` scans the framework body for banned tokens and exits non-zero on leak. Run before any commit that touches `core/` or framework docs. Future syncs from any reference adopter must pass this gate.

**Consequences**:
- Framework reads universally — adopters don't see "this is the reference project's tool" on first read.
- Future maintainers can sync new patterns from any reference adopter without re-introducing specifics into the framework body.
- One-time cleanup cost (~3-4h, this ADR); ongoing cost = run the purity script before commits to `core/` (sub-second).
- Some recipe text loses its concrete sharpness (`apps/web/lib/i18n/translations.ts` → `<web-app>/lib/i18n/translations.ts`). The trade-off is acceptable because every adopter project substitutes its own path on first read.

**Alternatives considered**:
- *Retain specifics with a disclaimer* ("the reference project is the reference adopter; replace these names with your own") — rejected. Disclaimers don't survive skim-reading; the first 90 seconds of adopter contact decides whether they keep reading.
- *Move all specifics to a dedicated `docs/EXAMPLES-FROM-REFERENCE.md`* — rejected. Separates lessons from their context (the recipe), weakens recipe usefulness.
- *Do nothing; specifics are "color" that helps the reader trust the rules* — rejected. Production-pedigree signal lives in the README origin paragraph, not in every recipe body.

**Verification**:
- `tools/check-framework-purity.sh` exits 0 against the post-ADR-026 tree.
- Frozen history documents (DESIGN-DECISIONS / audits / KPI / CONDUCTOR-V0.2-DESIGN / CURRENT_WORK / SESSION_HANDOFF) untouched.
- Adapter `transform.sh` files keep their functional path defaults (excluded from purity scan).

---

## ADR-027 — Generalized server-secret-leak pattern is universal (refines ADR-018)

**Status**: Accepted (2026-06-26)

> **Numbering note**: the dispatching plan tasked this as "ADR-024", but ADR-024 (TDD + Systematic Debugging recipes) and ADR-025 / ADR-026 already exist. Per the plan's own instruction ("find the highest existing ADR number and append after it"), this lands as ADR-027. Title intent (refines ADR-018) is unchanged.

**Context**: ADR-018 drew the hookify port boundary that placed `block-service-role-key-in-client` out of scope (rejected item 2: "BaaS-specific service-role-key string. Conductor's recipes don't mandate any specific BaaS."). The reasoning was correct for the *vendor literal* — a specific product's key name is not universal. But it over-rejected: the underlying hazard (a server-only credential placed in a file that ships in the client bundle) is a universal security failure mode independent of any vendor. Every web/mobile stack has a client bundle, every such stack has server-only secrets, and every such stack ships those secrets to all users if the split is violated.

**Decision**: Refine ADR-018's boundary. The vendor literal (a specific key name) stays project-local — adopters who want to match an exact product key name override the placeholder. But the *name-shaped generalized secret pattern* appearing in a *client-glob path* is a universal hazard and ships as a framework hookify template `block-server-secret-in-client` (always-on, `action: block`). Two new install-time placeholders make it adopter-tunable without baking any vendor name into the framework body:

- `${CONDUCTOR_CLIENT_GLOB}` — paths that ship in the client bundle. Default is a lookahead-free alternation (`(src/(components|hooks|pages|ui)|public)/.*\.(ts|tsx|js|jsx)$`) to avoid PCRE-engine uncertainty across hookify versions. Override via env `CONDUCTOR_CLIENT_GLOB`.
- `${CONDUCTOR_SERVER_SECRET_PATTERN}` — credential-name shapes that must never appear in client code. Default `(SERVICE_ROLE_KEY|SERVICE_ROLE|_SECRET_KEY|_PRIVATE_KEY|ADMIN_API_KEY|SECRET_ACCESS_KEY)` — generic env-var naming conventions, NOT a vendor product name. `SERVICE_ROLE` is a common credential-tier naming convention (privileged vs. anon/public), not a vendor reference. Override via env `CONDUCTOR_SERVER_SECRET_PATTERN`.

Both substitutions live only in the adapter's `substitute_hookify_template()` defaults (overridable per project), never in framework prose. The template FILE itself contains only the `${CONDUCTOR_CLIENT_GLOB}` / `${CONDUCTOR_SERVER_SECRET_PATTERN}` placeholders — no literal secret name — so it stays purity-clean under `tools/check-framework-purity.sh`.

**Consequences**:

- ADR-018's boundary is **unchanged for vendor literals**: a specific product's exact key name still does not ship in the framework. This ADR carves only the *generic, name-shaped* pattern back in. No conflict with ADR-018; this is a strict refinement.
- Conductor consumer projects now receive a 13th always-on hookify template that blocks committing a server-only-shaped credential into a client-bundled path. The block is overridable (narrow `CONDUCTOR_CLIENT_GLOB`, or relocate the file) for genuine server-only files that happen to match the default client glob.
- The template body cites no vendor or stack specifics — it describes the client/server key split abstractly (public/anon key on the client, secret/privileged key on the server), consistent with ADR-026 framework-purity.
- Adopters whose secret naming differs (e.g. a different prefix convention) set `CONDUCTOR_SERVER_SECRET_PATTERN` at install time; no template edit required.

**Alternatives considered**:

- *Leave it fully rejected per ADR-018.* Rejected — that conflates the vendor literal (correctly out of scope) with the universal hazard (in scope). The client-bundle secret-leak is one of the most common and highest-severity mistakes across all stacks; omitting it weakens the framework's security baseline for no purity gain (the placeholder default carries no vendor name).
- *Ship a hard-coded secret-name list in the template body.* Rejected — that would either bake a vendor-specific literal into the framework (purity violation) or freeze the list, preventing per-project tuning. Placeholders keep the template clean and adopter-tunable.
- *Use a PCRE lookahead in the client glob to exclude server dirs precisely.* Rejected for the default — lookahead support varies across hookify regex engines; a lookahead-free alternation is portable, and adopters needing precision override `CONDUCTOR_CLIENT_GLOB`.

## ADR-028 — Recipe-scoped hookify templates

**Status**: Accepted (2026-06-26)

**Context**: Until now every hookify template in `adapters/claude/hookify-templates/` was always-on — Step 4.5 of `transform.sh` emitted all of them on every install. That works for templates whose hazard is universal across stacks (false-completion claims, force-push, server-secret-in-client). But some hazards are only meaningful for projects that opted into a particular stack shape. The `database-discipline` recipe (ADR-028's motivating case) ships two SQL-specific rules — `warn-create-table-without-access-control` and `warn-security-definer-without-search-path` — that are pure noise in a project with no relational store. Emitting them always-on would either inject SQL-specific warnings into non-SQL projects or force the framework to keep stack-shaped rules out entirely.

**Decision**: Introduce a recipe-scoped emission mechanism. A `.recipe-scoped` map file in the hookify-templates directory lists `<template-basename>  <recipe-name>` pairs. `transform.sh` Step 4.5 consults this map per template:

- If the template's output basename appears in `.recipe-scoped`, it is emitted **only** when its recipe is present in `--recipes`. Otherwise it is skipped with a logged reason (`skipped (requires --recipes=<recipe>)`).
- If the template is **not** listed in `.recipe-scoped`, it remains always-on (the default, unchanged behavior).

The map's comment lines begin with `#`; the gating grep anchors on `^<basename>[[:space:]]` so comments never match. The `.recipe-scoped` file is a leading-dot file and is not picked up by the `*.local.md.template` glob, so the emit loop never tries to treat it as a template.

This couples the SQL hookify rules to the `database-discipline` recipe: select the recipe and the two SQL rules install alongside the recipe rule; omit it and neither the recipe nor its rules appear.

**Consequences**:

- The always-on hookify set stays vendor- and stack-neutral. Stack-shaped rules (SQL access-control, SECURITY DEFINER search_path) ship opt-in, tied to the recipe that makes them relevant.
- Always-on templates (including `block-server-secret-in-client` from ADR-027) are unaffected — they are not listed in `.recipe-scoped`, so the new gating block is a no-op for them.
- Adding a future stack-shaped rule is a two-line change: drop the template and add one line to `.recipe-scoped` mapping it to its recipe. No `transform.sh` edit required.
- The mechanism is recipe-name-based, not adapter-specific. If other adapters add hookify-equivalent runtime hooks, the same `.recipe-scoped` convention can apply per adapter.

**Alternatives considered**:

- *Keep all templates always-on; let adopters delete the irrelevant ones post-install.* Rejected — pushes stack-specific noise onto every adopter and burdens non-SQL projects with SQL warnings they must manually remove. Opt-in gating is the cleaner default.
- *Encode the recipe scope in the template's own frontmatter (e.g. a `recipe:` key) instead of a separate map.* Rejected — that would require the installer to parse each template's frontmatter before deciding whether to emit it, and would put installer-control metadata inside a file whose frontmatter is consumed by hookify at runtime (mixing concerns). A standalone map keeps installer logic and runtime rule definition separate.
- *Gate by file-path heuristics (e.g. emit SQL rules only if the target has `.sql` files).* Rejected — fragile (a fresh project may have no `.sql` files yet) and implicit. Explicit recipe selection is predictable and matches how every other recipe-scoped asset is chosen.

## ADR-029 — License change: MIT → Apache 2.0 + name trademark (supersedes ADR-007)

**Status**: Accepted (2026-06-28).

**Context**: ADR-007 chose MIT. The owner (LFamily Labs LLC) wants two things that plain MIT does not cleanly express together: (1) keep the project **fully open and free, including for commercial use** — developers may use CONDUCTOR to build and sell their own products, exactly like a normal open-source plugin; and (2) prevent someone from taking CONDUCTOR, **modifying and rebranding it, and passing it off as their own**. An earlier draft of this ADR briefly relicensed to PolyForm Noncommercial — that was wrong (it banned commercial use outright, the opposite of intent) and was reverted within the same window before any distribution.

**Decision**: License the **code** under the **Apache License 2.0** (permissive, OSI-approved, with an explicit patent grant and attribution-preservation requirements), copyright © 2026 LFamily Labs LLC. Protect the **name** separately:
- `LICENSE` = Apache 2.0 verbatim + a trademark-notice header. `package.json` `license` = `Apache-2.0` (root + VSCode extension).
- `NOTICE` (Apache §4(d)) carries the copyright + attribution that downstream forks must retain.
- `TRADEMARKS.md` states the policy: **take the code, not the name.** "CONDUCTOR" is a trademark of LFamily Labs LLC; Apache §6 grants no trademark rights, so forks may use the code freely (incl. commercially) but must rename and keep attribution, and may not imply they are the official project.

**Why this matches intent**: Apache 2.0 §4 forces any redistributor to (b) mark modified files as changed and (c) retain copyright/attribution/NOTICE — so a fork cannot silently strip authorship and pass off as original. The trademark on the name blocks the specific "rebrand-and-resell as CONDUCTOR" act. Everything else stays as open as MIT (slightly stronger, since Apache adds the patent grant). Note: a properly-renamed, properly-attributed fork is permitted — that is the open-source bargain, and is acceptable to the owner. (A hard legal ban on renamed competing resale would require a source-available license such as FSL or PolyForm Perimeter, which was considered and declined in favor of maximal adoption.)

**Timing / scope**: Done before any public distribution (private repo, not on npm/marketplace) — no prior MIT release to grandfather. Applies from v0.2.0 (tag + GitHub Release re-cut to include it).

**Consequences**:
- `docs/COMPARISON.md`'s "permissive / open" positioning is preserved (Apache 2.0 is as permissive as MIT). The brand is now explicitly protected.
- ADR-008 (no telemetry) unaffected. Still free, still no paid tier.
- **Not legal advice.** Registering the "CONDUCTOR" trademark is a separate legal step; an unregistered ™ claim has weaker protection. Have counsel confirm if enforcement matters.

**Alternatives considered**:
- *Stay MIT.* Workable, but MIT does not require marking changes as prominently and is silent on patents; Apache 2.0 is a strict improvement for the same permissiveness.
- *PolyForm Noncommercial.* Rejected — bans commercial use, the opposite of intent (this was the reverted misstep).
- *FSL / PolyForm Perimeter (source-available, ban competing resale).* Rejected for now — would legally block even renamed competing resale, but at an adoption cost; the owner prioritized openness + brand protection over a hard anti-compete clause. Revisit if rebrand-resale becomes a real problem.

## ADR-030 — Self-improvement is opt-in, propose-only, delta-based

**Status**: Accepted (2026-07-03)

**Context**: CONDUCTOR's VISION lists "not a silent auto-learner" as a non-goal, yet a real gap exists: no mechanism reads session trajectories to distil lessons. A prior counting-only observation approach produced noise, not signal (see `docs/specs/2026-07-03-conductor-self-improvement-reflector-design.md`). Recent research (ACE, GEPA, ExpeL) converges on an LLM "Reflector" that reads trajectories and emits small deltas, merged deterministically to avoid context collapse.

**Decision**: Ship self-improvement as an opt-in recipe (`self-improvement`) driving a new `reflector` role, at autonomy ceiling **L1+ (propose-only)**. The reflector reads trajectories (transcript pointer + git + retro), appends `ADD/UPDATE/STALE` lesson deltas to `docs/REFLECTION-PROPOSALS.md`, and stops. Lessons are a specialization of the `feedback` memory type; a deterministic non-LLM script prunes/decays/dedups them. Nothing is applied without human approval. Automation is per-adapter (a stop-hook trajectory log + a scheduled trigger on Claude), with a manual `/reflect` floor everywhere.

**Consequences**:

- The VISION non-goal is preserved and clarified: proposing is not silent learning; a one-clause addition makes the boundary explicit in `VISION.md` and `docs/PHILOSOPHY.md`.
- Reintroduces no SQLite/counter store — trajectories are read directly.
- L2 (auto-apply), retrieval scoring, Pareto rule variants, and procedural/"playbook" memory are explicitly future work, not built here.
- Introduces two new Claude-adapter emission mechanisms (a target-side script and a `.claude/commands/` file) that did not previously exist.

**Alternatives considered**:

- *Keep counting/metering only.* Rejected — the diagnosis that motivated this ADR is precisely that counters produce noise, not lessons.
- *Auto-apply accepted-by-heuristic lessons (L2).* Rejected for now — violates the propose-only boundary that keeps the capability inside the VISION non-goal; deferred to a later spec.
- *A standalone memory store for lessons.* Rejected — reuses the existing `feedback` type to avoid a second store and duplicate curation rules.

## ADR-031 — 2026 compatibility-matrix re-verification (multi-tool parity correction)

**Status**: Accepted (2026-07-04)

**Context**: `docs/COMPATIBILITY-MATRIX.md` (and the VISION capability table) dated 2026-05-03 marked hooks, sub-agent dispatch, custom named agents, per-task model routing, slash commands, and built-in memory as **Claude-only** (✅ Claude, mostly ❌ the other five — slash commands were already ⚠️ for Cursor). A first-party re-verification on 2026-07-04 (official docs / changelogs / tool GitHub repos, two verification passes) found this is materially out of date: all six tools now ship event hooks (Cursor v1.7; Gemini v0.26.0; Copilot CLI+cloud+VS Code; Codex default-on; Windsurf 12 events but no session/stop), sub-agents, custom named agents, per-task model selection, and slash commands; Copilot/Codex/Windsurf also have built-in managed memory. Windsurf was rebranded to **Devin Desktop** (June 2026) and its rules path moved to `.devin/rules/`.

**Decision**: Correct the matrix and VISION table to the verified tool-*capability* level, with an explicit **capability ≠ CONDUCTOR-emission** disclaimer: a ✅ means the tool documents the feature, not that a CONDUCTOR adapter compiles to it. Only first-party-confirmed cells are flipped; unverifiable claims (Codex hook/Automations dates, Cursor local transcript path, Cursor current-version Memories, Gemini AGENTS.md-by-default) are hedged with ⚠️ and footnotes rather than shipped as ✅. Actually emitting hooks / a scheduled Reflector job / native agents for the five non-Claude adapters is scoped as **Phase 2** (`docs/specs/2026-07-03-multitool-parity-reverification-SPEC-B-handoff.md`), not done in this documentation pass.

**Consequences**:

- The framework's public honesty improves: the matrix no longer understates competitors, and it clearly separates "tool can" from "CONDUCTOR does."
- A concrete adapter backlog is now visible: emit hooks + scheduling + (optionally) native agents per tool; update the Windsurf adapter target to `.devin/rules/`. Genuine residual gaps are documented (Windsurf has no session/stop hook events; Gemini/Windsurf-desktop have no native scheduler; Gemini/Codex scope by nested-file hierarchy not glob; Copilot coding-agent has no transcript API).
- ADR-004 (sub-agents stay Claude-only in CONDUCTOR) is unchanged as a *design* choice, but is now flagged as a revisit candidate given native sub-agents exist everywhere.

**Alternatives considered**:

- *Flip every ❌ to ✅ from the broad research.* Rejected — some claims (ship dates, Cursor local transcript, Cursor current Memories) lack a first-party source; shipping them as fact would repeat the original error in the opposite direction.
- *Leave the matrix; only note "hooks now exist."* Rejected — the user's audit was explicitly "check every Claude-only cell," and most were stale, not just hooks.
- *Build the non-Claude adapter emission now.* Rejected for this pass — large per-tool implementation; scoped as Phase 2 so the verified documentation correction ships first.

## ADR-032 — Cross-tool Reflector emission (Spec B Phase 2, first slice)

**Status**: Accepted (2026-07-04)

**Context**: ADR-031 corrected the matrix to show hooks/agents/commands are native on all six tools but flagged that CONDUCTOR did not emit them (capability ≠ emission). The highest-value slice is the self-improvement Reflector loop (ADR-030), which was Claude-only.

**Decision**: Emit the Reflector loop for the five non-Claude adapters, recipe-gated on `self-improvement`: a portable stdin-based trajectory logger (`core/reflector/trajectory-log.sh`, upsert-by-session) wired to each tool's nearest session-end hook (Cursor `.cursor/hooks.json` `stop`; Copilot `.github/hooks/*.json` `agentStop`; Gemini `.gemini/settings.json` SessionEnd; Codex `.codex/hooks.json` Stop; Windsurf `.windsurf/hooks.json` post_cascade_response_with_transcript), a `/reflect` command in each native format (Cursor skill, Copilot prompt file, Gemini TOML command, Codex skill, Windsurf workflow), a reflector agent where the tool has native agents (Cursor/Copilot/Gemini/Codex) or a `trigger: manual` rule (Windsurf), and the portable `prune-lessons.sh`. Hook-config files are written only when absent (never clobber a user's config; log a manual-merge note instead). The Windsurf adapter's rules target moves to `.devin/rules/` (preferred) per the 2026 Devin Desktop rebrand; legacy `.windsurf/rules/` is still read.

**Consequences**:
- The Reflector is genuinely multi-tool. The trajectory logger reads the transcript path from hook stdin (cleaner than the Claude dir-scan) and upserts by session, so turn-scoped (Codex `Stop`) and response-scoped (Windsurf `post_cascade_response`) hooks do not spam the index.
- Still open (Phase 2 remainder): full hook-set parity (agent-routing / commit / large-file guards on non-Claude), native scheduler wiring for weekly Reflector runs, and migrating the Claude trajectory hook to the same stdin approach.

**Alternatives considered**:
- *Merge into an existing hook config file.* Rejected — safe JSON merge in bash is fragile; write-only-if-absent + a manual-merge note is safer.
- *One agent/command format for all.* Rejected — each tool's format differs; per-tool wrappers around shared brief/persona text keep it DRY without faking a format.

## ADR-033 — Weekly Reflector scheduling (runner + docs, not auto-registration)

**Status**: Accepted (2026-07-05)

**Context**: After ADR-032 the Reflector loop is emitted for all six tools, but the actual weekly *reflection* only ran when a human typed `/reflect`. First-party research (2026-07-05) established that (a) headless invocation exists for every tool (`claude -p`, `codex exec`, `gemini -p`, `cursor-agent -p`, `copilot -p`, `devin -p`), but (b) native LOCAL schedulers exist only for Claude (Desktop Scheduled Tasks) and Codex (app Automations); Cursor/Copilot-cloud/Windsurf schedulers run on a cloud clone and cannot see the local, git-ignored `.conductor/trajectories/`. Registering an OS-level schedule (cron/launchd) is a machine/user action a repo installer cannot perform.

**Decision**: Emit a portable **`run-weekly.sh`** (auto-detects the first supported CLI on PATH, runs the reflect brief headless from the project root, no-ops when there are no trajectories; `CONDUCTOR_REFLECT_CLI` override, `CONDUCTOR_REFLECT_DRYRUN` preview) plus **`SCHEDULING.md`** (honest per-tool registration: OS cron/launchd as the universal local path, Claude Desktop tasks + Codex app automations as native-local, the cloud-scheduler trajectory-blind caveat, and GitHub Actions cron snippets with the committed-trajectory caveat). CONDUCTOR does NOT auto-register a schedule — it ships the runner + the guide and the user wires it once. The runner inlines the brief text rather than relying on `/reflect` slash-command resolution (unverified headless on Cursor/Windsurf).

**Consequences**:
- Self-improvement is now a complete loop the user can make autonomous with one documented cron line, while staying propose-only.
- Honest about limits: cloud schedulers are documented as trajectory-blind; the runner degrades to a no-op when no CLI is on PATH or no trajectories exist.
- Phase 2 remainder now: the REST of the hook set on non-Claude adapters, and migrating the Claude trajectory hook to the stdin approach.

**Alternatives considered**:
- *Auto-register cron/launchd from the installer.* Rejected — modifying a user's crontab/LaunchAgents from a repo transform is invasive and non-portable.
- *Per-tool runner scripts.* Rejected — one auto-detecting runner is DRY; the only per-tool difference is one headless command line, handled by a `case`.
- *Rely on native cloud schedulers.* Rejected — they cannot read local `.conductor/`; documented as such instead.

## ADR-034 — Workflow guards stay Claude-only pending a hook-config-merge redesign

**Status**: Accepted (2026-07-05)

**Context**: After the Reflector loop was made multi-tool (ADR-030/032/033), the last Phase-2 candidate was porting the remaining Claude hooks — `pretool-agent-routing` and the three guards (`commit-current-work`, `commit-test-coverage`, `large-file-read`) — to the five non-Claude adapters. A first-party feasibility study (2026-07-05) was run before building.

**Findings**:
- **`pretool-agent-routing`** validates Claude's Agent-tool sub-agent dispatch. CONDUCTOR keeps sub-agent *compilation* Claude-only (ADR-004), so this hook is genuinely Claude-specific — nothing to port.
- **`large-file-read` guard**: its core advice ("re-read with `offset`/`limit`") maps 1:1 only to **Gemini** (`read_file.offset/limit`, agent-visible deny) and near-cleanly to **Copilot** (`view` tool; arg names undocumented/UNVERIFIED). **Cursor** exposes no range param, its deny message reaches the *user* not the agent, and the file is already client-loaded (no I/O win). **Windsurf** (`pre_read_code`) can size-gate but has no range param. **Codex** reads via shell commands (no file-read tool; `PreToolUse` covers only Bash/apply_patch and "not all shell calls"), so the guard degrades to fragile command-regex sniffing.
- **Structural blocker (all guards)**: a guard is *always-on* (token economy) while the trajectory hook is *recipe-gated*, and single-config-file tools (Cursor `.cursor/hooks.json`, Gemini `.gemini/settings.json`, Windsurf `.windsurf/hooks.json`) require **both entries in one file**. Safe JSON merge in bash was deliberately avoided (ADR-032 wrote hook configs only-if-absent). Adding an always-on guard alongside the recipe-gated trajectory hook needs a hook-emission redesign (always-write a combined config with both entries, each runtime-gated) — larger than the guard's value.

**Decision**: Do **not** port the guards or agent-routing now. Keep them Claude-only; document the per-tool feasibility above so a future contributor can pick it up. The high-value Phase-2 work (the Reflector loop: emission + scheduling + unified stdin logging across all six tools) is complete. If the guards are pursued later, first land a hook-config-merge/emission redesign, then port the `large-file-read` guard to Gemini (clean) and Copilot (verify `view` args), size-gate variants for Cursor/Windsurf, and document Codex as unsupported.

**Alternatives considered**:
- *Force-port all guards to all five tools now.* Rejected — 15 translations, most low-value (soft-warns), several UNVERIFIED, blocked by the config-merge issue.
- *Build a bash JSON-merge helper first.* Deferred — real infrastructure work whose only current consumer is a low-value guard; revisit when a second always-on non-Claude hook is needed.

---

## ADR-035 — Instruction-fidelity-first context reduction (lossless before lossy)

**Status**: Accepted (2026-07-05)

**Context**: An audit of CONDUCTOR's token-economy assets (anti-pattern catalog, `meta-discipline.md` §5–6, `PROMPT-CACHING-GUIDE.md`, the token hooks) found that nearly every mechanism is pure raw token reduction, and the single mechanism that risks distorting the user's original instructions — §5.7 "auto-compact threshold" — shipped with **no safeguard** for preserving instructions through summarization. A primary-source verification pass (2026-07-05, Anthropic docs + engineering blog + the *Lost in the Middle* TACL 2024 paper) confirmed: (a) lossy summarization/compaction compresses the user's own turns and can silently drop the ask; (b) Anthropic's **API context editing** (`clear_tool_uses_20250919`, beta header `context-management-2025-06-27`) clears tool results / thinking blocks only and **never** user instructions or text messages, with a measured ~84% token reduction on a 100-turn eval; (c) recall degrades in the middle of long context ("context rot" / finite "attention budget"), so cutting stale tokens is genuinely valuable — but only if the user's intent is not among what is cut.

**Decision**: Adopt an explicit **lossless-before-lossy** ordering for context reduction, and treat instruction fidelity as the hard constraint that ranks the reducers:

1. Rewrite `meta-discipline.md` §5.7 from a bare "auto-compact" note into a two-tier rule: **lossless first** (drop stale tool results, never user turns), **lossy last** (summarization/compaction), with four mandatory compaction safeguards — durable instructions live in CLAUDE.md/rules (survive compaction), pass explicit `/compact` preservation instructions, prefer `/clear` between unrelated tasks, and re-verify the compacted note still carries the original instruction before continuing.
2. Add `docs/CONTEXT-EDITING-GUIDE.md` (Claude-only, parallel to `PROMPT-CACHING-GUIDE.md`) documenting the context-editing mechanism, its fidelity guarantee, the memory-tool pairing, and the `/compact` vs `/clear` levers, all with primary-source citations.

The universal rule states the tool-agnostic *principle* (cut stale tool output first, user instructions last); the concrete lossless *mechanism* is Claude-API-only and is documented in the adapter-scoped guide, consistent with R3 (Claude-only features stay out of universal rule bodies) and the honest per-tool degradation already used for prompt caching.

**Consequences**: The one [RAW/RISK] mechanism in the token-economy layer now has a fidelity safeguard. Non-Claude adapters inherit the principle via rule text but not the lossless API mechanism (no equivalent exists today) — recorded honestly in the guide's parity table. This is the P0 slice of a larger token-economy refresh; P1/P2 candidates (output-brevity directive, Tool Search Tool `defer_loading`, sub-agent total-vs-lead-context framing correction, model-lineup/pricing refresh, attention-budget rationale on the monolithic-rule anti-pattern) are deferred to follow-up ADRs.

**Alternatives considered**:
- *Put context-editing guidance in a universal recipe.* Rejected — the mechanism is Claude-API-only, so a tool-agnostic recipe would overpromise; the `docs/` adapter-scoped guide (matching `PROMPT-CACHING-GUIDE.md`) is the honest home.
- *Add a "never-compact / pin the original task" hook.* Deferred — no such API primitive exists; the CLAUDE.md-durability + re-verify discipline achieves the same outcome without inventing enforcement CONDUCTOR can't back.

---

## ADR-036 — Token-economy refresh P1/P2 (output brevity, deferred tools, sub-agent framing, model/pricing, attention-budget)

**Status**: Accepted (2026-07-05)

**Context**: ADR-035 shipped the P0 fidelity slice and deferred the remaining audit findings. The same primary-source verification pass (Anthropic docs + engineering blog, verified 2026-07) confirmed five more gaps, each now closed on the same branch: (1) the layer tracked output tokens as a *symptom* in KPI but gave **no directive** to be terse, despite output pricing ~5× input; (2) `meta-discipline.md` §5.5 referenced "deferred tool patterns" only abstractly, while Anthropic shipped a concrete **Tool Search Tool** (`defer_loading`, "over 85%" tool-context reduction, ~55K-token multi-MCP baseline); (3) the `no-sub-agent-dispatch` anti-pattern framed dispatch as a token *saver*, but Anthropic's own figures (agents ~4× chat tokens, multi-agent ~15×) show dispatch **raises total tokens** and only saves the *lead's* context; (4) §6 model tiers cited no current lineup/pricing and missed the fidelity evidence that cheaper models guess missing params where Opus asks; (5) the `single-monolithic-rule-file` anti-pattern explained cost but not the fidelity axis (attention budget / context rot / "minimal ≠ short").

**Decision**: Land all five as content refinements, keeping every claim tied to a primary source and every fidelity caveat that is CONDUCTOR's own inference labelled as such:

1. **New `meta-discipline.md` §5.9 (output brevity)** + **new Anti-Pattern 08 (`output-verbosity-narration`)** — answer-first, no re-printed file bodies, right-sized format, `max_tokens`; with an explicit fidelity guard (brevity never drops required substance).
2. **§5.5 rewrite** — concrete Tool Search Tool `defer_loading` mechanism + numbers; mirrored into Anti-Pattern 07's fix.
3. **`no-sub-agent-dispatch` §2.1** — honest caveat: dispatch is a context-isolation + fidelity win, not a total-token saver; when NOT to dispatch (shared context / tight dependencies).
4. **§6 lineup/pricing snapshot** (Haiku 4.5 $1/$5 · Sonnet 5 $3/$15 · Opus 4.8 $5/$25 · Fable 5 $10/$50) + **§6.4 recast as a fidelity rule** (Opus asks on missing params, cheaper models guess = distortion).
5. **`single-monolithic-rule-file` §2.1** — second axis: attention-budget/context-rot dilution + the cache-first-vs-attention-middle placement tension.

**Consequences**: The token-economy layer now covers the output side (previously only tracked, never governed) and states the *fidelity* rationale behind rules that were previously justified on cost alone. Model names/prices are a dated snapshot with a re-verify note (tier labels stay generation-agnostic so the rule doesn't rot). No new enforcement/hooks — all changes are rule-text + catalog, so all six adapters inherit them via `transform.sh` with no Claude-only surface beyond the already-Claude-only Tool Search Tool citation.

**Alternatives considered**:
- *Fold P1/P2 into ADR-035.* Rejected — ADR-035 accurately scoped itself to the P0 fidelity slice; a separate ADR keeps the decision history honest about what shipped when.
- *Add an output-token guard hook.* Deferred — output length is a soft-discipline concern; a Stop-hook that scolds on high output tokens is possible but low-value versus the rule text, and would be Claude-only. Revisit if KPI shows output-token regressions in practice.

---

## ADR-037 — `git-hygiene` recipe + Claude-only Stop hook (shared-repo discipline)

**Status**: Accepted (2026-07-07)

**Context**: A reference adopter hit a git-workflow-hygiene collapse — an orchestrator interpreted "work without conflicting with the other session" as *create git worktrees* (never requested), never cleaned them up, and never deleted branches after their PRs merged: ~130 stale local branches + 34 local-only commits + orphan worktrees. Nothing was actually lost (all merged), but the hygiene collapse made completed work **look** unmerged/lost, triggered a false "backup ≠ applied" scramble, and cost large reconciliation time and trust. The adopter codified a battle-tested rule ("Git hygiene / shared-repo discipline", 7 obligations) + a non-blocking Stop hook, written project-agnostically. This is a universal failure mode for anyone using git with autonomous agents — a strong CONDUCTOR candidate.

**Decision**: Ship it as a new **opt-in recipe `git-hygiene`** (not a universal rule) plus a **recipe-scoped Stop hook** `stop-git-hygiene-guard`:

1. **Recipe over universal rule** — keeps the 5-bundle universal floor lean (token economy, ADR-014 / anti-pattern 03); git hygiene is opt-in per project (recommended for any shared/multi-session git repo). The recipe body installs on all six tools via the generic per-adapter recipe loop.
2. **Hook is Claude-only** (consistent with ADR-034: workflow guards other than the Reflector stay Claude-only). It follows the `stop-trajectory-log` mechanism — always emitted, **runtime self-gated** on the recipe marker (`.claude/rules/git-hygiene.md`), non-blocking (always exits 0), 15-min cool-down, `CONDUCTOR_SKIP_GIT_HYGIENE=1` / `CONDUCTOR_GIT_HYGIENE_BRANCH_MAX` overrides. It detects extra worktrees, local-only commits (`git log --branches --not --remotes`), and abnormal local-branch counts, and injects a cleanup reminder. On the five non-Claude tools the recipe's rule text is the enforcement (honest degradation; Windsurf genuinely lacks Stop events).
3. **Sanitized** (R2): reference-adopter rule IDs mapped to CONDUCTOR equivalents (real-code verify → quality-gates Q4; compaction durability → meta-discipline §5.7; confirm-before-reckless-op → meta-discipline AMB-3/4; review gate → quality-gates); the concrete target branch ("develop") generalized to "your integration/target branch" cross-referencing the `branch-strategy` recipe.

**Consequences**: Recipe count 11 → 12, hook templates 7 → 9 (this pass also synced the 0.3.0 `stop-trajectory-log` count that several docs had left at 7). CI smoke installs `git-hygiene` and asserts the hook emits + is executable. No new role/runtime scripts (the guard is self-contained). The hook is the first recipe-scoped shell Stop hook beyond the Reflector; it reuses the self-gate pattern rather than inventing new infra.

**Alternatives considered**:
- *Universal rule instead of recipe.* Rejected — always-on git-hygiene taxes every adopter's prefix (incl. trivial solo repos) and bloats the universal floor; opt-in fits the "recipes = project-specific discipline" model.
- *Cross-tool hook emission (all six).* Deferred — per ADR-034 that needs bespoke per-adapter blocks + hook-config JSON for five tools, and Windsurf lacks Stop events. The recipe rule text covers the non-Claude tools until (if) that larger cross-tool hook work lands.

---

## ADR-038 — `loop-engineering` recipe + Claude-only PreToolUse loop-guard (bounded, externally-verified agent loops)

**Status**: Accepted (2026-07-07)

**Context**: Autonomous agents work in loops ("do → check → fix → re-check until done"), and those loops fail in well-documented ways. A 5-source primary-research pass (peer-reviewed papers + Anthropic primary docs; findings in `docs/plans/2026-07-07-loop-engineering-research.md`) established: (a) **intrinsic self-correction is unreliable and can degrade quality** — models asked to fix their own work with no external signal flip correct answers to wrong (*LLMs Cannot Self-Correct Reasoning Yet*, Huang et al., DeepMind ICLR'24); real gains come from loops grounded in tests/tools (Reflexion, CRITIC); (b) **self-judgment of "done" is unreliable** — LLM-as-judge bias + systematic overconfidence (*Judging LLM-as-a-Judge*, NeurIPS'23), so "the model says it's done" is not evidence (the "early-victory" failure); (c) **unbounded loops run away** — infinite/oscillation loops were 95.6% cost-exhaustion/DoS in one study (*When Agents Do Not Stop*, 2026), and test-time compute saturates then hurts; (d) Anthropic's own guidance frames the loop as *gather→act→verify→repeat* bounded by `max_turns`/budget + human checkpoints, with a verify hierarchy of **rules/tests > visual > LLM-judge**. CONDUCTOR had implicit loops (quality-gates Q4, TDD, Reflector) but no first-class loop-engineering discipline. The user flagged this as a top-priority feature.

**Decision**: Ship an **opt-in recipe `loop-engineering`** encoding six obligations (G1 explicit done-criterion · G2 iteration+token budget · G3 require-progress · G4 escalate-on-stall · **G5 verify externally, never by self-judgment** · G6 oscillation/infinite-loop guard), plus a **Claude-only PreToolUse hook** `pretool-loop-guard`:

1. **Recipe over universal rule** — keeps the universal floor lean; opt-in per project. Body installs on all six tools via the generic recipe loop; the recipe's central axis (G5: external verification) is `quality-gates.md` Q4 applied inside the loop.
2. **Hook = PreToolUse soft-warn** (Claude-only, ADR-034). Registered with a `"*"` matcher (all tools, additive to the existing specific-matcher PreToolUse hooks — confirmed against Claude Code hook docs). It tracks a per-session signature (`tool + sha1(tool_input)`) in a `$TMPDIR` trace, and emits a non-blocking `permissionDecision: ask` reminder when the same action repeats ≥ `CONDUCTOR_LOOP_REPEAT_MAX` (default 5; oscillation/no-progress) or session tool calls ≥ `CONDUCTOR_LOOP_BUDGET` (default 120; runaway). Self-gates on `.claude/rules/loop-engineering.md`; fail-open (any error / missing python3 / missing stdin → allow silently, never blocks a tool call); per-session cool-down. All logic is in a python3 block wrapped in try/except for robustness.
3. **Evidence-grounded, not invented** — every obligation cites the research; the recipe teaches "external verify > self-judge" as the core rule.

**Consequences**: Recipe count 12 → 13, hook templates 9 → 10 (5 PreToolUse + 5 Stop). First PreToolUse recipe-scoped guard; first `"*"`-matcher hook. Verified across 8 functional conditions + 6 exception cases + concurrency + non-blocking exit-0 + no-repo-pollution (see `docs/plans/2026-07-07-loop-engineering-recipe.md`). CI smoke installs the recipe and asserts the hook emits, is executable, is registered, and settings.json stays valid JSON.

**Alternatives considered**:
- *Universal rule instead of recipe.* Rejected — same token-floor reasoning as ADR-037; opt-in fits the model.
- *Hard-block on runaway (`deny` / exit 2).* Rejected — a loop guard must never break legitimate work; `ask` surfaces the concern and lets the orchestrator decide. Fail-open throughout.
- *Cross-tool hook emission.* Deferred — same ADR-034 constraints; the recipe rule text covers non-Claude tools.
- *Enforce G5 (external-verify) via a hook.* Deferred — "did you verify before claiming done" is hard to detect generically at the tool layer; left to the rule text + quality-gates Q4. The hook targets the mechanically-detectable failures (oscillation, runaway).
