---
paths:
  - "**"
---

---
rule_id: meta-discipline
rule_name: "Originality, ambiguity handling, never-skip, token economy, model routing"
severity: ABSOLUTE
applies_to: ["all-tools"]
violation_count: 8+
enforcement:
  - hook: pretool-agent-routing
  - llm-self-discipline
linked_rules:
  - workflow
  - quality-gates
  - operations
---

# Meta-Discipline — How CONDUCTOR Stays CONDUCTOR

> Bundles M1 (framework originality), M2 (token economy reference), M3 (model routing reference), M5 (ABSOLUTE rules never skip — cross-link), and the ambiguity policy (ACT-WITH-DECLARATION default + AMB-1..7 triggers).

## 1. Process Over Speed (W5 cross-link)

User shortcut phrases never grant permission to skip workflow steps. See `workflow.md` section 4 for the full rule. This file restates it because process-over-speed is the meta-rule that protects every other rule.

---

## 2. Framework Originality (M1)

CONDUCTOR core assets MUST NOT borrow names, terminology, or structural conventions from other agent frameworks. The originating project records this as an explicit ABSOLUTE rule:

> "Looks similar in concept" is fine. "Took mine" is not.

In practice, this means:

- Do NOT use external framework names (the names of competing or inspirational multi-agent / agent-CLI frameworks) anywhere in `core/`, `roles/`, `recipes/`, or `hooks/`.
- Do NOT copy directory structures from external frameworks (e.g., a `crews/` folder borrowed from a known framework).
- Do NOT use external framework's role vocabulary verbatim (e.g., specific agent role names that are trademarked patterns of other tools).
- DO compare and reference external frameworks in design documents (`docs/`) where the comparison is the point — but those references stay out of universal rule bodies.

### 2.1 Why

The user's framework is their craft. Borrowing names dilutes provenance and creates licensing / attribution ambiguity. CONDUCTOR pays in invented terminology so adopters get a clean, self-contained vocabulary.

### 2.2 CONDUCTOR's own vocabulary (use these)

- **orchestrator** — the user-facing leader thread.
- **role** — a specialized sub-task profile (planner / builder / reviewer / helper / designer / scribe).
- **dispatch** — the act of delegating a task to a role.
- **dispatch brief** — the ≤2K-token instruction object passed at dispatch.
- **stop condition** — explicit done-criteria for a dispatched task.
- **flat-with-leader** — orchestration topology where roles never dispatch each other; only the orchestrator dispatches.
- **Single-Agent Mode** — fallback for tools without native sub-agent support; orchestrator + helper collapse into one thread.
- **AMB triggers** — the 7-item ambiguity catalog that forces ASK behavior.
- **ACT-WITH-DECLARATION** — proceed-with-best-guess + surface the assumption.
- **universal rule** vs **recipe** — universal rules apply to every adopter; recipes are opt-in.

### 2.3 Verification

Originality is verified by grep at every CONDUCTOR commit:

```bash
# Run from conductor repo root.
# Should return zero matches inside core/, roles/, recipes/, hooks/.
grep -RIE 'MetaGPT|AutoGen|CrewAI|LangGraph|ChatDev|Aider|Cursor|Continue|Cline|SWE-agent' core/ roles/ recipes/ hooks/
```

References to these names live ONLY in the CONDUCTOR repo's `docs/CONDUCTOR-V0.2-DESIGN.md` and `docs/DESIGN-DECISIONS.md` where comparison is the point.

---

## 3. Ambiguity Handling — ACT-WITH-DECLARATION default + AMB triggers force ASK

### 3.1 Default behavior

Unless an AMB trigger fires, the orchestrator proceeds with best-guess interpretation AND surfaces the assumption in the response prefix:

```
Assumption: I'm interpreting "footer cleanup" as web only (<web-app>/...).
Plan: ...
```

This format gives the user a one-glance catch — they can correct in a single follow-up turn before any cost is sunk.

### 3.2 AMB triggers — when to switch to ASK

If ANY of the following fire, the orchestrator MUST switch from ACT-WITH-DECLARATION to ASK:

| Trigger ID | Pattern | Example | Required action |
|---|---|---|---|
| AMB-1 | Deictic references — "this", "like before", "similar to that one" | "this needs to be cleaner" | ASK + present 3 candidate referents as multiple-choice |
| AMB-2 | Unspecified scope — single vs all, web vs mobile, dev vs prod | "fix the footer" | ASK + (web only / mobile only / both) |
| AMB-3 | External system invocation that is non-trivially reversible | DB migration, payment ops, mass email | ASK once: "dev only / prod only / both?" |
| AMB-4 | Merge or push to a protected branch | `gh pr merge`, `git push origin main` | ASK + explicit confirmation required |
| AMB-5 | Design decisions (color, layout, copy tone) | "make this button more modern" | ASK + 2-3 visual / copy alternatives |
| AMB-6 | Library or dependency addition | "add an image cropper" | ASK + 3 candidates + trade-off table |
| AMB-7 | User manual action required (env vars, dashboard config) | "you need to set up the webhook" | ASK + numbered steps + wait for user confirmation |

### 3.3 ASK template (multiple-choice)

When ASK fires, the orchestrator uses this template — NOT open-ended questions:

```markdown
**Situation**: <one-sentence ambiguity summary>

**Option A**: <action A> — Trade-off: <pros / cons>
**Option B**: <action B> — Trade-off: <pros / cons>
**Option C**: <action C> — Trade-off: <pros / cons>
**Other**: free-form one-line response if A/B/C don't fit

**Recommended default**: <A | B | C> — reason: <one-line>
```

### 3.4 Why multiple-choice

- User cognitive load drops: 5-second decision vs 30+-second free response.
- Trade-offs are pre-analyzed, raising decision quality.
- Fewer follow-up turns (the orchestrator already considered the obvious alternatives).

### 3.5 The "verify before recommending" sub-rule

When ASK fires for AMB-6 (dependency) or AMB-5 (design), the orchestrator MUST verify each candidate before recommending:

- Library candidates: confirm name + maintenance status + license.
- Design candidates: render or describe each visually.

A recommendation without verification = an opinion, not a recommendation. Mark it as such if you can't verify.

---

## 4. ABSOLUTE Rules Never Skip (W6 cross-link)

No user instruction grants exemption from rules marked `severity: ABSOLUTE`. See `workflow.md` section 5 for the full rule. The orchestrator that catches itself about to skip MUST surface the violation explicitly (R5 surface obligation).

This rule is restated here because meta-discipline is the file most adopters read first when porting CONDUCTOR to a new tool — and ABSOLUTE-never-skip is the single most-violated rule in production history.

---

## 5. Token Economy (M2)

> Goal: minimize wasted context. Applies to orchestrator and every role.

### 5.1 Read discipline (large files)

- **Check size first** before opening. Use `wc -l` or grep with line numbers.
- **Prefer Grep over Read** for symbol lookup. Use `-A` / `-B` context. Read only when 50+ contiguous lines are needed.
- **Range reads (offset / limit) are mandatory** for files > 200 lines. Default `limit: 100`; expand only if proven necessary.
- **Never `cat` a whole rules file or large spec.** Grep for the section first, then range-read.

### 5.2 Hidden injection awareness

Some tools auto-inject skill / library docs when certain file paths are touched. These injections add hidden tokens (often 200-600 per Read). Be deliberate:

- Skip auto-inject when Grep is sufficient.
- When a Read is unavoidable, batch related Reads in a single response so cache reuses the prefix.

### 5.3 Sub-agent dispatch discipline

- Cap dispatch briefs at ~2K tokens. Reference files by path; do not paste content.
- Tell the dispatched role the EXACT files to read. Don't make the role grep blindly.
- Specify background execution for any task expected to take > 2 minutes wall-clock.

### 5.4 Cache-friendly prompt order (Claude adapter)

When prompt caching is available (Claude / Anthropic SDK):

```
[Cache prefix — low-frequency change]
1. Universal rules (5 bundles)
2. Project CLAUDE.md
3. Selected recipes

[cache_control: { type: "ephemeral" } boundary]

[Per-turn — high-frequency change]
4. Recent turn history
5. Tool results
6. User's new message
```

Full guide: the CONDUCTOR repo's `docs/PROMPT-CACHING-GUIDE.md` (not installed into your project).

### 5.5 Tool description compression

When > 30 tools are loaded, the description footprint becomes a measurable cost. Use deferred / lazy-loaded tool patterns where supported.

### 5.6 Touched-file rule scoping

Use `paths:` (Claude) / `globs:` (Cursor) / `applyTo:` (Copilot) to scope rule files to the source areas they govern. A rule that fires only when a relevant file is touched is cheaper than a rule loaded into every turn.

### 5.7 Auto-compact threshold

When the conversation context approaches the model's window cap, summarize older turns into a compact note and free the budget. Some tools auto-compact at ~80%; others rely on the orchestrator to trigger it.

### 5.8 .ignorefile maintenance

Each tool has its own ignore file (`.claudeignore`, `.cursorignore`, `.aiderignore`, etc.). Keep these in sync — they prevent expensive accidental Reads of build outputs, large lockfiles, or vendored code.

---

## 6. Model Routing (M3)

The orchestrator classifies every task and selects model tier explicitly. The user does NOT specify the model per request — that responsibility belongs to the orchestrator.

### 6.1 Tier 1 — Conceptual / complex (Opus-tier)

Trigger if any of:

- Design concept change ("revamp X", "new pattern", palette swap).
- Architecture redesign or primitive redesign.
- Multi-file migration (5+ files, cross-cutting).
- Cross-platform parity work (web ↔ mobile, desktop ↔ web, etc.).
- Multi-surface root-cause hunt.
- System-level decision (data model, auth flow, billing logic).
- Anti-pattern audit + refactor.
- Documentation work that synthesizes multiple concerns.

### 6.2 Tier 2 — Routine (Sonnet-tier, default for most work)

- Single-file or single-component tweak.
- New page using established shell.
- Icon / copy / translation swap.
- Minor responsive / padding fix.
- Simple CRUD following established service-layer pattern.
- Spec text update.
- Translation key propagation across N locales (pattern established).

### 6.3 Tier 3 — Trivial (Haiku-tier)

- Read a file, return a specific value.
- Rename a variable in 1 file.
- Trivial text edits.

### 6.4 Override rule of thumb

> When in doubt, **upgrade one tier**. Cost difference is modest; risk of Sonnet misinterpreting conceptual work is large.

### 6.5 Surface the choice

When ambiguous, the orchestrator surfaces its model choice in the dispatch announcement:

> "Dispatching to `builder` (Opus) — multi-file refactor across 5 components."

This gives the user a chance to override before tokens are spent.

### 6.6 Per-tool applicability

| Tool | Model routing applies? |
|---|---|
| Claude Code | Yes (Agent tool's `model` parameter; PreToolUse hook validates explicit choice) |
| Cursor | Yes (Composer model picker — orchestrator chooses by rule) |
| Copilot | Limited (model selection is account-level, less per-task control) |
| Gemini / Codex / Windsurf | Limited (single-model context typical) |

On limited-routing tools, the orchestrator still classifies the task — even if it can't change the model — because the tier informs effort level (low / medium / high reasoning) and dispatch budget.

---

## 7. Orchestration Topology — Flat-with-Leader (M5)

CONDUCTOR adopts a flat-with-leader topology:

- The orchestrator (main thread) is the only user-facing leader.
- All role agents are dispatched 1:1 by the orchestrator. They do NOT call each other.
- A role agent that needs multi-step work returns intermediate results; the orchestrator decides the next dispatch.

### 7.1 Why no nested dispatch

- Solo dev mental model: one leader, several helpers.
- Nested dispatch causes context to accumulate at every layer → token blow-up.
- Production experience: nested dispatch attempts surfaced bugs faster than they delivered features.

### 7.2 Enforcement

On Claude Code, the `pretool-agent-routing` hook validates that:
- `subagent_type` is one of the registered roles (not `general-purpose`).
- `model` is explicitly set.
- The dispatcher is the orchestrator (not another role).

On other tools, the rule text serves as the constraint.

---

## 8. Cross-tool enforcement summary

| Discipline | Claude Code | Cursor | Copilot | Gemini | Codex | Windsurf |
|---|---|---|---|---|---|---|
| Originality grep | Pre-commit script (orchestrator's responsibility) | Same | Same | Same | Same | Same |
| AMB-1..7 trigger ASK | Rule text + LLM self-discipline | Same | Same | Same | Same | Same |
| Token-economy Read discipline | Rule text + Stop-hook reminder when wasteful patterns spike | Rule text | Rule text | Rule text | Rule text | Rule text |
| Model routing | PreToolUse hook validates explicit `model` | Composer picker manual | Account-level only | Single model | Single model | Single model |
| Flat-with-leader | PreToolUse hook validates dispatcher | Single-Agent Mode (no sub-agents) | Same | Same | Same | Same |

The honest summary: meta-discipline is enforced by rule text on every tool, with hook-based extras on Claude Code only.
