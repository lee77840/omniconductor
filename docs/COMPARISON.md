# COMPARISON — CONDUCTOR vs other tools

Honest comparison of CONDUCTOR against the major existing options. Updated 2026-07-09 — CONDUCTOR version currency lives in [`CHANGELOG.md`](../CHANGELOG.md).

## Headline matrix

| | GSD (`get-shit-done`) | SpecKit | BMAD | Cursor Rules | Plain CLAUDE.md | **CONDUCTOR** |
|---|---|---|---|---|---|---|
| **Multi-tool target** | 14+ runtimes | A few | A few | Cursor only | Claude Code only | 6 tools, all with working adapters (Claude / Cursor / Copilot / Gemini / Codex / Windsurf) — npm-published (`npx omniconductor`) |
| **Setup weight** | Heavy (60+ skills) | Heavy (phases, ceremonies) | Heavy (sprint-style) | Light (rules only) | Trivial | Light kernel (5 universal rules + 8 roles) + 13 opt-in recipes + verified hook set |
| **Sub-agent orchestration** | Yes | Yes | Yes | No | Manual | Yes — five native profile formats plus Windsurf role workflows |
| **Spec-as-you-go enforcement** | Soft (encouraged) | Yes (gates) | Yes (artifacts) | No | No | ABSOLUTE everywhere; verified Stop guard on Claude/Codex, installed completion checklist elsewhere |
| **Two-stage code review** | Yes | Yes | Yes | No | No | Eight-role topology on all six; mechanical guard subset on Claude/Codex and native review/checklist elsewhere |
| **Token economy rules** | Bonus | Bonus | Not specifically | No | No | Built-in from day 1; instruction-fidelity-first since 0.4.0 (ADR-035/036) |
| **Self-improvement loop** | No | No | No | No | No | Opt-in `self-improvement` Reflector — propose-only, human-approved (ADR-030/032/033), emitted on all 6 tools |
| **Agent-loop / git discipline** | No | No | No | No | No | Opt-in `loop-engineering` (bounded, externally-verified loops, ADR-038) + `git-hygiene` (shared-repo discipline, ADR-037) recipes |
| **Memory pattern** | No | No | No | No | No | Universal 4-type pattern; native managed memory on Claude/Copilot/Codex/Windsurf, documented fallbacks elsewhere |
| **Bilingual (한/영)** | Translations available | English-first | English-first | English-first | DIY | First-class (한/영, README + marketing) |
| **Origin** | Single-author theory | Microsoft research roots | Indie author | IDE vendor | None | One year of production iteration at LFamily Labs |
| **Maturity** | High (many skills) | High (well-documented) | High (community) | Medium | N/A | All 6 adapters working + CI-validated, npm-published; 1.0 shipped 2026-07 (current version in `CHANGELOG.md`) |
| **License** | MIT (varies) | MIT | Commercial-friendly | Proprietary IDE | N/A | Apache 2.0 + CONDUCTOR-name trademark (ADR-029) |
| **Telemetry** | Varies | None | None | Cursor opt-in | None | None ever (ADR-008) |
| **Uninstall path** | Per-skill manual delete | Per-phase manual delete | Per-artifact manual delete | None (rules accumulate) | N/A | `transform.sh --uninstall` (manifest-tracked, restores backups) — ADR-020 |

## When to pick which

### Pick GSD / BMAD if:
You want maximum depth, a large skill catalog, an existing community, and you don't mind heavy setup. GSD is the maximalist choice for users who want every workflow phase covered with a dedicated skill.

### Pick SpecKit if:
You want a Microsoft-pedigree, well-documented spec-driven workflow with clear phase gates. Strong for enterprise teams that already use Microsoft developer tooling.

### Pick Cursor Rules if:
You only use Cursor and don't anticipate switching tools. Cursor Rules give you what Cursor natively supports — no abstraction overhead. (You can later cross-port to CONDUCTOR if you adopt a second tool.)

### Pick plain CLAUDE.md if:
You only use Claude Code, want zero framework, and prefer to extend incrementally. CONDUCTOR's value mostly disappears for single-tool, single-rule-file users.

### Pick CONDUCTOR if:
- You use 2+ AI coding tools on the same project (or plan to).
- You want production-shape orchestration with ABSOLUTE enforcement of the things that actually matter at solo / small-team scale.
- You value bilingual (한/영) onboarding.
- You want a small, opinionated kernel — not a maximalist superset.
- You've shipped code and felt the pain of stale docs and merged regressions.

## How CONDUCTOR is different from a "rules format converter"

CONDUCTOR is NOT just a tool that translates rules between formats. It is opinionated content + workflow + memory pattern that happens to be portable.

If you only want format conversion, you can write a 50-line script that reads `*.md` and re-emits them with different front-matter. CONDUCTOR's universal rules (operations / quality-gates / meta-discipline / spec-as-you-go / workflow) plus the 13 opt-in recipes are the value; the multi-tool transform is the delivery vehicle.

## Honest weaknesses of CONDUCTOR

- **No installer GUI.** Bash adapters + the `npx omniconductor` CLI only. Power-user tool. (A VSCode-extension launcher is Phase 2 — ADR-023/025.)
- **Mechanical guard coverage is capability-specific.** Claude gets the full set, Codex gets the verified native subset, and other adapters avoid translating unverified hook contracts. All six receive role entry points and the opt-in Reflector loop.
- **Live verification is not complete.** All 6 adapters are emit-verified in CI; live rule-loading is probed per tool by `tools/live-verify.sh`, and the current per-tool status lives in the generated table in `docs/ADAPTER-LIVE-VERIFICATION.md` (single-sourced from adapter metadata).
- **No community yet.** No Discord, no Twitter/X presence. You're an early adopter.
- **Tool fragmentation risk.** If 12 new tools launch in 2026, we cannot keep up. Mitigated by documented adapter contribution path (`docs/CONTRIBUTING.md`).
- **Guard asymmetry.** Claude receives the full verified guard set and Codex receives the verified native subset. Cursor, Copilot, Gemini, and Windsurf retain the same obligations through native rules plus only the lifecycle/recipe hooks whose contracts are verified.
- **External review plugins are optional.** Every adapter emits the base `code-reviewer` role; a compatible third-party plugin may add another review signal but is not required for the two-stage workflow.
- **Mobile rule (project-specific) is React Native flavored.** If your stack is native iOS or native Android, that rule is mostly noise — but it's project-specific and lives in your adapted output, not in `core/`.

## Honest strengths

- **Production pedigree.** Every rule earned through a real shipping incident at LFamily Labs. Not theoretical.
- **Honesty over feature inflation.** ADR-004 says we will NOT fake-polyfill sub-agents anywhere; ADR-031 documents per-tool capability vs what CONDUCTOR actually emits. Other multi-tool projects gloss over this.
- **Bilingual moat.** Korean solo-dev community is meaningful and underserved.
- **Apache 2.0, no telemetry, no paid tier — fully open and commercial-friendly.** Only the **CONDUCTOR** name is reserved (trademark), so nobody can pass off a modified copy as the original. Same permissive footing as MIT competitors, with brand protection (ADR-029).
- **Small, opinionated kernel.** 5 universal rules (plus 13 strictly opt-in recipes and 10 hook templates) vs GSD's 60 skills. If our rules are wrong for you, you'll know quickly and can move on. No 6-month sunk cost.

## Verdict

If you only ship in Claude Code and you love opinionated tooling, CONDUCTOR is a strict upgrade over plain CLAUDE.md.

If you ship in multiple tools, CONDUCTOR is the only option that treats portability as a first-class requirement rather than a future maybe.

If you want a maximalist phase-gated SDLC tool with broad runtime support and an existing community, pick GSD or BMAD; CONDUCTOR is intentionally smaller and more opinionated.

## Conflict resolution: Superpowers + CONDUCTOR on the same project

> Added 2026-05-09 per ADR-019, finding from `docs/audits/competitive-analysis-2026-05-09.md` (P1c).

Superpowers (a Claude Code plugin set offering brainstorming / planning / TDD / debugging skills) and CONDUCTOR overlap in workflow scope. Running both unmoderated double-loads guidance into every turn, hurts cache hit rate, and creates ambiguity about which workflow the orchestrator should follow.

### Workflow overlap matrix

| Workflow area | Superpowers | CONDUCTOR | Overlap risk |
|---|---|---|---|
| Brainstorming | `superpowers:brainstorming` skill | `core/universal-rules/workflow.md` Plan-first + AMB triggers | High — both frame the requirements stage, prompts compete |
| Planning / writing plans | `superpowers:writing-plans` | `workflow.md` 7-step + `meta-discipline.md` ACT-WITH-DECLARATION | High — both produce `.plan.md`-style artifacts |
| Plan execution | `superpowers:executing-plans` / `subagent-driven-development` | Centralized + Role-Specialized orchestration (ADR-010) | High — both manage sub-agent dispatch but with different guardrails |
| TDD | `superpowers:test-driven-development` | `quality-gates.md` Q3 (test-coverage sync) | Medium — Superpowers prescribes red/green/refactor; CONDUCTOR prescribes coverage parity. Compatible if order is fixed. |
| Debugging | `superpowers:systematic-debugging` | None — left to project judgement | Low — adopt Superpowers' debugging skill freely; no conflict. |
| Code review | `superpowers:requesting-code-review` / `receiving-code-review` | `quality-gates.md` Q1 (pre-commit) + Q2 (pre-merge) two-stage | Medium — Superpowers covers etiquette; CONDUCTOR covers gate enforcement. Stack as etiquette-on-top-of-gates. |
| Git worktrees | `superpowers:using-git-worktrees` | None | None — Superpowers complements, not conflicts. |
| Verification before completion | `superpowers:verification-before-completion` | `quality-gates.md` Q1/Q4 | Low — same intent, different surface. Pick one; CONDUCTOR's hook-enforced version is stricter. |

### Cache-hit impact

ADR-014 sets a 95% cache-hit floor as CONDUCTOR's SLA. Loading both rule sets into the cacheable prefix doubles the volatile-content surface (Superpowers' SKILL.md descriptions update, CONDUCTOR's `core/universal-rules/*` update) — every change in either invalidates the cache. Empirically, projects that run both without reconciliation drop from 100% to 60-80% hit rate within two weeks. Run `tools/measure-tokens.sh --latest` after enabling both to baseline; if hit rate drops below 95%, follow option A or B below.

### Recommended patterns

**Option A — CONDUCTOR only (recommended for new projects)**

Use CONDUCTOR's universal rules + roles + recipes. Skip Superpowers entirely. The
5-rule kernel covers planning, spec-as-you-go, quality gates, operations, and
meta-discipline; the 8 base roles cover orchestration through Tier 3 utility. Add
Superpowers later only if a specific skill is missing.

**Option B — Superpowers as primary, CONDUCTOR recipes only (for projects already on Superpowers)**

Keep Superpowers in charge of workflow. Cherry-pick CONDUCTOR recipes that don't overlap — `monorepo`, `i18n`, `coding-conventions`, `branch-strategy`, `auto-mock-data` — without installing the universal rules or roles. Procedure:

```bash
# Install only recipes (no universal-rules, no roles, no hooks):
bash adapters/claude/transform.sh <target> --recipes=monorepo,i18n,coding-conventions --no-prompt
# Then manually delete the universal-rules and agent files emitted by transform.sh:
rm <target>/.claude/rules/{workflow,spec-as-you-go,quality-gates,operations,meta-discipline}.md
rm <target>/.claude/agents/*.md
```

> Note: a future `--recipes-only` flag (separate dispatch) will streamline this. Until then, the manual deletion above is the supported procedure. The recently shipped `--uninstall` (ADR-020) reverts the entire install — including recipes — so a Superpowers-primary user can clean-slate via `transform.sh <target> --uninstall` and re-run with the recipes-only convention above when it lands.

**Option C — Both (NOT recommended, requires manual reconciliation)**

If you must run both:
1. Disable overlapping Superpowers skills (`brainstorming`, `writing-plans`, `executing-plans`, `verification-before-completion`) by removing them from the active plugin set, or by adding a project-level rule that says "skill X disabled, see CONDUCTOR's `workflow.md` instead".
2. Re-measure cache hit rate after one week. If below 95%, escalate to option A or B.
3. Document the active reconciliation in `CLAUDE.md` so the orchestrator doesn't oscillate between guidance sources.

### Cross-reference

- Audit basis: `docs/audits/competitive-analysis-2026-05-09.md` — full Superpowers feature inventory and cache-hit rationale.
- ADR-019 in `docs/DESIGN-DECISIONS.md` — decision record for the cleanup batch that produced this section.
- ADR-014 in `docs/DESIGN-DECISIONS.md` — 95% cache-hit floor SLA.
