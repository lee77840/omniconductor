---
rule_id: meta-discipline
rule_name: "Originality, ambiguity handling, never-skip, token economy, difficulty routing"
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

> Bundles M1 (framework originality), M2 (token economy reference), M3 (vendor-neutral difficulty routing), M5 (ABSOLUTE rules never skip — cross-link), and the ambiguity policy (ACT-WITH-DECLARATION default + AMB-1..7 triggers).

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
- **Single-Agent Mode** — fallback when sub-agent dispatch isn't available or isn't emitted for the tool; orchestrator + helper collapse into one thread.
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

Tool schemas (names, descriptions, JSON Schemas) are billed as input tokens on **every** request, plus a small per-model tool-use system prompt. A typical multi-MCP setup (e.g. a code host + a chat platform + an error tracker + a couple of observability servers) can consume ~55K tokens in definitions before any work begins.

When many tools are loaded, use **deferred / lazy tool loading** so only tool *names* enter the prefix and full schemas are fetched on first use:

- **Claude API**: the Tool Search Tool (`defer_loading: true` per tool, or on an `mcp_toolset`) — Anthropic reports "over 85%" reduction in tool-definition context while preserving the prompt cache. At least one tool must stay non-deferred.
- **This session** already demonstrates the pattern via `ToolSearch`: tool names appear in system reminders, but invoking one requires fetching its schema first.

See Anti-Pattern 07 (skill / MCP eager-load).

### 5.6 Touched-file rule scoping

Use `paths:` (Claude) / `globs:` (Cursor) / `applyTo:` (Copilot) to scope rule files to the source areas they govern. A rule that fires only when a relevant file is touched is cheaper than a rule loaded into every turn.

### 5.7 Context reduction WITHOUT instruction loss

When the window fills, there are two ways to free budget — and they are NOT equal on fidelity. The orchestrator MUST prefer the lossless one.

- **Lossless (preferred) — drop stale tool results, not user turns.** Old tool outputs (file reads, command output, search hits) are the bulk of a bloated window and carry near-zero forward value once acted on. Clearing them frees budget without touching a single user instruction. On the Claude adapter this is the API context-editing feature (`clear_tool_uses`): it clears tool results / thinking blocks only and **never** user instructions or text messages. See `docs/CONTEXT-EDITING-GUIDE.md`.
- **Lossy (last resort) — summarizing older turns.** Summarization / compaction (`/compact`, auto-compact near the window cap) compresses **everything, including the user's own turns**, so it can silently drop or distort the original instruction. Use only after lossless clearing is exhausted.

**Compaction safeguards (mandatory whenever lossy compaction runs):**

1. Keep durable instructions in the always-loaded rule / context file (CLAUDE.md / project rules), not in conversation history — they survive compaction because they are re-loaded every turn.
2. When you must compact, pass explicit preservation instructions (e.g. `/compact keep the original task statement, acceptance criteria, and open TODOs verbatim`).
3. Between unrelated tasks, prefer a full reset (`/clear`) over letting the window bloat and then lossily compacting.
4. After any compaction, re-verify the compacted note still carries the original instruction before continuing. If in doubt, ask the user to restate — never proceed on a possibly-distorted summary.

Rationale: raw token count is a finite **attention budget**, and the goal is the *smallest set of high-signal tokens* — but never at the cost of the user's original intent. Stale tool results are the first thing to cut; user instructions are the last.

### 5.8 .ignorefile maintenance

Each tool has its own ignore file (`.claudeignore`, `.cursorignore`, `.aiderignore`, etc.). Keep these in sync — they prevent expensive accidental Reads of build outputs, large lockfiles, or vendored code.

### 5.9 Output brevity

Provider pricing and model ratios change, but unnecessary output always consumes
latency, context, and often additional cost. The orchestrator's own responses are a
directly controllable expense:

- **Answer, don't narrate.** Skip preamble ("Great question! Let me…"), postamble, and restating what the user already said. Lead with the result.
- **Match verbosity to the task.** A one-line answer for a one-line question; reserve tables and step-by-steps for genuinely multi-part work.
- **Don't echo file bodies back.** After an edit, state what changed by reference — do not re-print the file.
- **Cap bounded artifacts.** Use `max_tokens` (Claude adapter) when the expected output has a known ceiling.

**Fidelity guard:** brevity trims *the model's prose*, never *required substance*. Do not drop a warning, a caveat, a failing-test result, or a step the user must act on in the name of being terse. When forced to choose, completeness beats brevity. (This trade-off caveat is CONDUCTOR discipline, not an Anthropic-documented rule.)

See Anti-Pattern 08 (verbose output / narration).

---

## 6. Difficulty Routing (M3)

The orchestrator classifies every task into the exact portable tier below. The
classification is the invariant; a tool adapter translates it into that tool's
current model-selection or reasoning control. Never infer task difficulty from a
vendor model name, and never downgrade a declared tier because a cheaper or newer
model exists.

### 6.0 First-use configuration gate

Before the first role dispatch, verify that `.conductor/model-routing.json`
exists and contains this tool's Tier 1/2/3 entry. If it is missing (for example,
after a manual adapter install or an upgrade), pause role dispatch and ask the
user to run:

```bash
npx omniconductor models configure --target=<tool> .
```

Do not invent a model, silently downgrade a Tier, or edit role files from the
conversation. The deterministic installer owns role generation. After the
configuration command regenerates tool-native files, reload/restart the tool
when its native role registry does not hot-reload. The user's original task may
continue in the main thread, but newly generated role routing begins only when
the tool can see those files.

### 6.1 Tier 1 — Conceptual / complex

Trigger if any of:

- Design concept change ("revamp X", "new pattern", palette swap).
- Architecture redesign or primitive redesign.
- Multi-file migration (5+ files, cross-cutting).
- Cross-platform parity work (web ↔ mobile, desktop ↔ web, etc.).
- Multi-surface root-cause hunt.
- System-level decision (data model, auth flow, billing logic).
- Anti-pattern audit + refactor.
- Documentation work that synthesizes multiple concerns.

### 6.2 Tier 2 — Routine (default for most work)

- Single-file or single-component tweak.
- New page using established shell.
- Icon / copy / translation swap.
- Minor responsive / padding fix.
- Simple CRUD following established service-layer pattern.
- Spec text update.
- Translation key propagation across N locales (pattern established).

### 6.3 Tier 3 — Trivial

- Read a file, return a specific value.
- Rename a variable in 1 file.
- Trivial text edits.

### 6.4 Override rule of thumb

> When in doubt, **upgrade one tier**. The risk of under-reasoning conceptual work is larger than the incremental latency or cost.

This is a **fidelity** rule, not only cost caution. On conceptual or
instruction-dense work, an underpowered or low-effort configuration is more likely
to fill gaps by guessing. Route by fidelity risk, not by token price alone.

### 6.5 Surface the choice

When ambiguous, the orchestrator surfaces its difficulty choice in the dispatch announcement:

> "Dispatching to `builder` (Tier 1 — conceptual / complex) — multi-file refactor across 5 components."

This gives the user a chance to override before tokens are spent.

### 6.6 Per-tool translation

| Tool | Default translation | Version-update behavior |
|---|---|---|
| Claude Code | Saved Tier mapping; current-family aliases are recommended by setup | Family aliases track the provider family; exact IDs remain user-selectable. |
| Codex | Saved Tier mapping plus Tier 1/2/3 → high/medium/low reasoning effort | Exact current IDs are revalidated against the local catalog when available. |
| Gemini CLI | Saved Tier mapping; provider semantic aliases are recommended by setup | Aliases follow the provider's complexity classes. |
| GitHub Copilot | Saved exact Tier mapping in custom-agent `model` | Account, plan, client, and organization policy may reject or replace a selection. |
| Cursor | Saved exact Tier mapping in custom-agent `model` | Account, plan, and administrator policy may cause provider fallback. |
| Windsurf | Saved `Adaptive` requirement, announced in each role workflow | Workflow format has no model field or selector-state API; enforcement is advisory-session. |

The orchestrator MUST still classify the task when the tool cannot mechanically
switch a model. The Tier then controls reasoning depth, review strictness, dispatch
budget, and the explicit announcement. Saved model choices never change the Tier
triggers in §6.1–6.3, and unavailable models require explicit reconfiguration—never
an automatic downgrade.

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

On the other five tools, the native eight-role surface plus this rule text serves
as the routing constraint; no Claude Agent-tool matcher is claimed or translated.

---

## 8. Cross-tool enforcement summary

| Discipline | Claude Code | Cursor | Copilot | Gemini | Codex | Windsurf |
|---|---|---|---|---|---|---|
| Originality grep | Pre-commit script (orchestrator's responsibility) | Same | Same | Same | Same | Same |
| AMB-1..7 trigger ASK | Rule text + LLM self-discipline | Same | Same | Same | Same | Same |
| Token-economy Read discipline | Rule text + Stop-hook reminder when wasteful patterns spike | Rule text | Rule text | Rule text | Rule text | Rule text |
| Difficulty routing | PreToolUse hook + saved model | Tier + saved model (provider fallback possible) | Tier + saved model (policy-controlled) | Tier + saved semantic alias | Tier + saved model + effort | Tier + Adaptive advisory |
| Flat-with-leader | PreToolUse hook validates dispatcher | Rule text (tools have native sub-agents; role emission is a later adapter phase) | Same | Same | Same | Same |

The honest summary: every tool receives the same Tier contract. Mechanical model
switching is used only where the tool exposes a verified project-scoped control.
Windsurf preserves the Tier and saved Adaptive requirement in workflow text because
its selector cannot be inspected or pinned by a project workflow.
