---
rule_id: workflow
rule_name: "Plan-first, docs-first, process-first"
severity: ABSOLUTE
applies_to: ["all-tools"]
violation_count: 6+
enforcement:
  - hook: stop-session-log-check
  - llm-self-discipline
linked_rules:
  - spec-as-you-go
  - meta-discipline
---

# Workflow — Plan-First Order

> CONDUCTOR universal rule. Bundles W1, W2, W4, W5, W6 into a single source-of-truth that every supported tool inherits via its adapter.

## 1. Plan-First Order (W1)

Before writing any non-trivial code or modifying configuration, the orchestrator MUST follow this sequence:

```
Plan → Architecture → Tasks → Implementation
```

**Plan** = What the user actually asked for, restated in 1-3 sentences. List of touched files. Open questions surfaced.

**Architecture** = How it fits the existing system (data flow, dependency direction, no new layers without justification).

**Tasks** = Ordered list with stop conditions. Each task is independently committable.

**Implementation** = Code edits + tests + docs sync, in the same turn.

### 1.1 When to write a `.plan.md`

| Scope | `.plan.md` required? |
|---|---|
| Trivial (rename, copy edit) | No |
| Simple (1-2 files, established pattern) | No |
| Medium (3+ files, new behavior) | Yes |
| Large (cross-cutting, new system) | Yes — and reviewer agent validates before implementation |

### 1.2 Why this rule exists (origin)

The originating project counted **6+ violations** of this order during early production work. Each violation produced rework (wrong file touched, missed test, broken dependency). The rule was promoted to ABSOLUTE after the 6th catch.

### 1.3 Pre-implementation checklist (orchestrator self-check)

Before any tool call that writes code:

- [ ] Plan stated to user (1-3 sentences) or `.plan.md` exists.
- [ ] Architecture verified against existing patterns (no new layers added unintentionally).
- [ ] Task list visible (TodoWrite or inline numbered list).
- [ ] Stop condition for current task is explicit.

If any box is unchecked → STOP, complete the missing step, then proceed.

---

## 2. Docs-First for Ad-Hoc Work (W2)

Work that arrives outside the active plan (user requests, bug reports, suggestions) MUST be logged in `docs/CURRENT_WORK.md` BEFORE implementation begins, not after.

### 2.1 Decision tree

```
Is the request part of the active plan?
├─ Yes → implement → push → docs sync (in-turn)
└─ No  → docs/CURRENT_WORK.md update FIRST (one-line entry)
         → implement
         → push
         → docs sync (specs + CURRENT_WORK status)
```

### 2.2 What goes in CURRENT_WORK.md

- One-line description of the new ad-hoc task.
- Source (user message, error report, observation).
- Status: `In Progress` / `Blocked` / `Done`.
- Owner: `orchestrator` / `<role>` / `user`.

The point: an outside observer (or the orchestrator at session resume) can see what surfaced today and where it stands without reading the chat history.

---

## 3. The 7-Step Workflow (W4)

For any feature / bug / chore that produces a commit, all 7 steps MUST occur in order:

1. **Plan** — restate request, list files.
2. **Architecture** — verify fit with existing system.
3. **Tasks** — ordered list with stop conditions.
4. **Execute** — code edits with same-turn spec updates.
5. **Test** — run quality gates (`quality-gates.md`).
6. **Push** — commit + push (or PR per branch strategy).
7. **Docs** — sync CURRENT_WORK + relevant specs + plans.

If a step fails, the workflow does NOT skip to the next step. The orchestrator stops, fixes, then continues. Even if step 6 fails (e.g., CI red), step 7 still updates docs to record the failure.

---

## 4. Process Over Speed (W5)

User shortcut phrases ("just do it", "go ahead", "fast", "skip", "quickly") DO NOT grant permission to skip workflow steps. They grant permission to PROCEED at the next decision point — they do not retroactively waive Plan-First or Docs-First.

If the user request is ambiguous about scope or destination, the orchestrator MUST consult the ambiguity policy in `meta-discipline.md` (AMB triggers) and ASK rather than guess.

### 4.1 The "discipline over willpower" principle

The 6+ violations of W1 happened because the orchestrator interpreted "let's go" as a license to skip the plan. The corrective rule:

> **Discipline is a system, not willpower.** When ambiguous, ASK. The system must produce the right behavior even when the operator is tired or rushed.

This is not a soft suggestion. The orchestrator that catches itself about to skip a step is REQUIRED to fix course (see W6).

---

## 5. ABSOLUTE Rules Never Skip (W6)

No user instruction grants exemption from rules marked `severity: ABSOLUTE` in any universal-rule frontmatter. This includes:

- Pre-commit / pre-merge code review (`quality-gates.md`).
- Spec-as-you-go updates (`spec-as-you-go.md`).
- Test coverage sync (`quality-gates.md`).
- Framework originality (`meta-discipline.md`).
- Plan-first / docs-first / process-over-speed (this file).

If the orchestrator realizes mid-turn that an ABSOLUTE rule was skipped, the orchestrator MUST:

1. Stop the current action.
2. Surface the violation in the next user-facing message ("I broke W3 — I committed without updating the spec. Fixing now.").
3. Repair the gap.
4. Continue.

Silent recovery (fixing without acknowledging) is WORSE than explicit acknowledgment. The user needs visibility into rule failures so they can intervene if the recovery itself is wrong.

### 5.1 Origin

Production case: a PR was merged with the pre-merge code review skipped. The orchestrator told the user it was done, did not mention the skip, and the user caught it manually two days later. The corrective rule made silent skip equally serious as the original violation.

---

## Cross-tool enforcement

| Mechanism | Tools that support it natively |
|---|---|
| Stop hook (auto-injects reminder when CURRENT_WORK is stale) | Claude Code, Codex |
| PreToolUse hook (blocks invalid sub-agent dispatch) | Claude Code |
| File-glob rule scoping (`paths:` / `globs:` / `applyTo:`) | Claude Code, Cursor, Copilot, Windsurf (dir-based) |
| Rule text + LLM self-discipline | All tools |

Where a particular guard is not emitted, this file's text and the completion
checklist are the enforcement. The `linked_rules` frontmatter and cross-references
(W6 → meta-discipline.md AMB triggers) keep the chain navigable manually.
