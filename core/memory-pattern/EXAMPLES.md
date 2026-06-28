# Memory pattern — worked examples (PLACEHOLDER — P1 fills with sanitized real examples)

> **Status (P0 foundation)**: this file shows the SHAPE of each memory type via skeleton examples. P1 will fill with sanitized real examples derived from the reference adopter's accumulated memory.

## Example 1 — type: `user`

**Filename**: `user_profile.md`

```markdown
---
name: user-profile
description: who the user is and how they collaborate
type: user
---

- Korean speaker; bilingual onboarding preferred for headline material.
- Senior developer; can read code in TS / Python / Go / Rust without explanation.
- New to <some-specific-area>; benefits from concrete examples there.
- Prefers terse responses; no trailing summary unless asked.
- Reviews PRs same day; expects fast iteration.
```

**Use it for**: knowing how to format responses, what background context to assume, what NOT to over-explain.

---

## Example 2 — type: `feedback`

**Filename**: `feedback_no_silent_recovery.md`

```markdown
---
name: no-silent-recovery
description: when a rule is broken mid-turn, surface it explicitly; never silently fix and move on
type: feedback
---

When you realize you broke a rule mid-turn (skipped a phase, used the wrong agent type, etc.), STOP and call it out in the next user-facing message. Then fix the gap. Continue.

**Why**: silent recovery hides a class of recurring bugs from the user, who then can't help correct the upstream cause. Surfaced violations build trust over time.

**How to apply**: in the next message after the violation, lead with one line acknowledging the rule + the fix. Don't bury it in a bullet at the end. Don't omit it.
```

**Use it for**: any rule violation. Read this memory before deciding to "just quietly do better next time".

---

## Example 3 — type: `project`

**Filename**: `project_launch_blockers.md`

```markdown
---
name: launch-blockers
description: pre-launch blockers and their resolution dates
type: project
---

- **Payment-provider live activation**: blocked on business registration. Resolved YYYY-MM-DD. NOW UNBLOCKED.
- **Bank-aggregator production**: deferred to post-launch (manual entry MVP first). NOT a launch blocker.
- **iOS push notifications**: pending app store review. Target: YYYY-MM-DD.

**Why**: avoids re-asking the user the same status question every session.

**How to apply**: before recommending work on a blocked item, check this list. If the entry says BLOCKED, surface the blocker before doing the work.
```

**Use it for**: project-state questions. Decay fast — verify before acting on entries older than 2 weeks.

---

## Example 4 — type: `reference`

**Filename**: `reference_external_systems.md`

```markdown
---
name: external-systems
description: where information lives in external systems
type: reference
---

- **Payment provider live IDs (products, prices, webhooks)**: provider dashboard → Live mode → Products. Backup: `<your-secrets-vault>/payment-live.json`.
- **DNS records**: DNS provider account `<your-dns-org>`. CNAME / A records documented in `docs/legal/dns-snapshot-YYYY-MM-DD.md`.
- **Email infra dashboard**: <your-email-provider>.com console.
- **Cron monitoring**: hosting provider's deployments tab → Cron Jobs.
```

**Use it for**: "where do I find X?" questions. NEVER include actual secrets in memory entries — only pointer to the source-of-truth.

---

## MEMORY.md index — example

When you save a memory file, add a one-line pointer to `MEMORY.md`:

```markdown
- [User Profile](user_profile.md) — Korean senior dev; terse responses; bilingual onboarding
- [No Silent Recovery](feedback_no_silent_recovery.md) — surface rule violations explicitly
- [Launch Blockers](project_launch_blockers.md) — payment-provider live UNBLOCKED; iOS push pending
- [External Systems](reference_external_systems.md) — pointers to payment / DNS / hosting dashboards
```

The index is ALWAYS LOADED at session start (when the tool supports it). Keep ≤ 200 lines. Archive older entries by removing them from the index when no longer relevant; the source files stay on disk in case you need to retrieve.

## Pattern conventions

- File names: `<type>_<short-slug>.md` (snake_case).
- Title in body: human-readable.
- Frontmatter `description:` is what the index uses; keep ≤ 80 chars.
- For `feedback` and `project`: always include **Why** and **How to apply** lines. Without these, the entry is just trivia.
- For `user`: bullet list of facts. No need for Why/How.
- For `reference`: bullet list of pointers. NEVER inline the secret/data — just pointer to source.
