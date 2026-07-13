---
rule_id: spec-as-you-go
rule_name: "Same-turn spec update + real-time docs sync"
severity: ABSOLUTE
applies_to: ["all-tools"]
violation_count: 5+
enforcement:
  - hook: stop-session-log-check
  - llm-self-discipline
linked_rules:
  - workflow
  - quality-gates
---

# Spec-as-you-go — Same-Turn Documentation Sync

> Bundles W3 (spec update in same turn as code edit) and O1 (real-time docs sync). Documentation drift is the most common rule violation in production; the rule treats it as a code-level concern, not a "will do later" concern.

## 1. The Same-Turn Update Rule (W3)

Code change without same-turn doc update is a rule violation, period.

### 1.1 What "same turn" means

If the orchestrator (or a delegated role) edits a source file in turn N, the corresponding spec / architecture / decision doc MUST be updated **in the same turn N**, not in a follow-up turn, not in an end-of-session batch, not in tomorrow's commit.

### 1.2 What needs same-turn update — by change type

| Code change | Doc to update (same turn) |
|---|---|
| New API route / endpoint | spec for that area + frontmatter `api_routes:` list |
| New page / route | spec for that area + frontmatter `pages:` list |
| New component (reusable) | spec for that area + frontmatter `components:` list |
| New service / hook | spec for that area + frontmatter `services:` / `hooks:` list |
| Behavior change (existing flow) | "Flow" or "Known constraints" section of relevant spec |
| New DB table / column | DB schema spec section (or dedicated `DATABASE.md`) |
| New environment variable | env-vars section of relevant spec + onboarding doc |
| New external service integration | architecture doc + services index |

### 1.3 Why same-turn (not end-of-session)

End-of-session batching always loses fidelity. By turn N+5, the orchestrator no longer remembers that turn N also touched a database column. Stop-hook reminders catch some of this post-hoc, but the rule is designed to make Stop-hook unnecessary in the first place.

Documented production failure: a multi-file refactor changed 4 service signatures. The session ended without spec update. Days later a different agent edited one of those services, read the stale spec, and reverted to the old signature. The fix took longer than the original refactor.

### 1.4 Where to put a new spec

If the area you're touching does not yet have a `docs/specs/<area>.md`, CREATE IT in the same turn. Use `core/docs-templates/specs/_example.md` (shipped by every CONDUCTOR adapter) as the starting point.

---

## 2. Real-Time Docs Sync (O1)

When work is committed and pushed, the orchestrator MUST update the following docs in the same turn:

- `docs/CURRENT_WORK.md` — session state, what was done, what's next.
- `docs/REMAINING_TASKS.md` (if it exists) — mark completed tasks, surface new ones.
- `docs/TASKS.md` (if it exists) — phase-level checklist.
- The relevant spec(s) per the table in section 1.2.
- `docs/INDEX.md` (if a new doc was created in this turn).

### 2.1 The "completed task delete" sub-rule

When a task in CURRENT_WORK.md or TASKS.md is moved to status `completed`, it should be DELETED in the next session boundary, not left as historical clutter. The session log itself is the historical record. CURRENT_WORK.md is for what is current, not what was done last week. (Full rule: `operations.md` section 2.)

### 2.2 Referenced-fact currency — update EVERY place a changed fact lives

When a change alters a fact that other docs also state — a count ("7 anti-patterns"), an enumerated list (a catalog index, a table of files / recipes / tiers), a version or price, a cross-reference, or a renamed path — the same-turn sync includes **every** doc that repeats that fact, not only the file you edited. A value that is true in one file and stale in three others is a documentation bug; the reader trusts whichever file they open first, so a half-updated fact is worse than an obviously-old one.

The mechanic (before declaring the turn complete):

1. **Grep for the old value** — the old count, the removed name, the renamed path. Every hit is a candidate to update, or to *consciously* leave (e.g. a dated historical milestone entry, which stays as a record).
2. **If the change has no home, give it one.** A new decision / mechanism / guarantee that no existing doc states must be recorded: extend the most relevant doc, or CREATE a new one and register it in `docs/INDEX.md`. A change that is real but unrecorded is not done.
3. **Architectural decisions additionally get an ADR** (`meta-discipline.md` R5 → `docs/DESIGN-DECISIONS.md`).

Documented failure (this project): a catalog grew from 7 to 8 entries; the catalog's own index was updated but `CLAUDE.md`, `docs/INDEX.md`, and the changelog kept saying "7". Each was individually plausible and collectively wrong.

### 2.3 What the orchestrator does NOT update

- Session transcripts / chat exports — those are tool-specific and out of scope.
- External tracker tickets (Jira / Linear / GitHub Issues) — those are explicit user actions, not auto-sync.
- Generated files (lockfiles, type-gen output) — those self-update via tooling.

---

## 3. Frontmatter convention (CONDUCTOR schema)

Spec files use YAML frontmatter so adapter `transform.sh` can route them. The CONDUCTOR-native fields:

```yaml
---
spec_id: <kebab-case-area-name>
api_routes:
  - "/api/foo"
  - "/api/bar"
pages:
  - "/foo"
components:
  - FooCard
services:
  - getFooById
hooks:
  - useFooState
---
```

Per-tool transformations:

- **Claude Code / Codex**: keep as-is in `docs/specs/<area>.md`. The verified
  Stop-hook contract checks the same session/spec completion conditions.
- **Cursor / Copilot / Windsurf**: same file path, frontmatter preserved. Tool-specific scoping (`globs:` / `applyTo:`) added by the relevant adapter when the file lives under `.cursor/rules/` or `.github/instructions/`.
- **Gemini / Codex**: file is referenced by path inside the single GEMINI.md / AGENTS.md.

---

## 4. Enforcement mechanism matrix

| Mechanism | Trigger | Action |
|---|---|---|
| `stop-session-log-check` (Claude/Codex hook) | Recent commit + stale CURRENT_WORK.md | Block or reject completion with a reminder in the tool's verified hook dialect |
| `stop-session-log-check` (Claude/Codex hook) | Source files changed > 3 + zero spec files touched | Reject completion with a spec-as-you-go reminder |
| Rule text (Cursor/Copilot/Gemini/Windsurf) | Same as above | Completion checklist; operator verifies |

When this specific guard is not emitted, the orchestrator MUST self-check before declaring a turn complete:

1. Did this turn write to source files? → spec update done?
2. Did this turn produce a commit? → CURRENT_WORK.md updated?
3. Did this turn complete a task? → status moved to `completed`, scheduled for delete?

If any answer is "no", the turn is not complete.

---

## 5. Test coverage sync (cross-link)

Test coverage sync (every new feature / changed behavior MUST have a corresponding e2e test added or updated in the same PR) is documented in `quality-gates.md` section 3. This rule and that rule are siblings: spec-as-you-go covers documentation; test coverage sync covers verifiability. Both are ABSOLUTE.
