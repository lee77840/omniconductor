# PHILOSOPHY — CONDUCTOR

The beliefs CONDUCTOR is built on. If you disagree with any of these, you will fight the framework.

## Core beliefs

### 1. Discipline is portable. Enforcement is not.

You can write down "always update the spec when you change the code" and it will read the same in any tool. But ONLY Claude Code can block your commit when you skip it. CONDUCTOR's job is to make the discipline portable across every tool — and to be honest that the *enforcement* degrades on tools that lack hooks.

The wrong move would be to fake enforcement (e.g., shell out from Cursor to run a check). That breaks fragile, surprises users, and lies about the model. Better: install the rule text on every tool and tell the user explicitly "your tool cannot block this; police it yourself."

### 2. Sub-agent isolation is a feature, not a bug.

In Claude Code, sub-agents do NOT inherit `CLAUDE.md`. Every dispatch must be self-contained. People complain this is verbose; it is — on purpose. Verbose dispatches are documentation of intent. Read 10 of your own old dispatches and you'll learn what you actually meant six months ago.

On non-Claude tools, there are no sub-agents. The orchestrator pattern still applies, but the human plays the orchestrator role manually: classify the task, choose the right "agent persona" mentally, write a self-contained prompt. Less automated, same discipline.

### 3. Spec drift is the silent killer.

Every team starts with great docs. Six months later, the docs lie. New contributors trust the lie. Bugs ship. CONDUCTOR makes spec updates ABSOLUTE — Claude blocks the push via Stop hook; on other tools, the rule text reminds the user every session. The reminder is annoying on purpose. The alternative is months-old docs misleading the next agent (or the next human, or future-you).

### 4. Two-stage review is cheap insurance.

Stage A (local pre-commit) catches the obvious mistakes before history records it. Stage B (PR pre-merge) provides an audit trail. Both run in seconds via specialized review agents (Claude) or rule reminders (other tools). Skip them once and you'll merge a regression you knew about.

### 5. Token economy isn't optional.

Reading a 2,000-line file when you needed 30 lines is wasteful — but more importantly, it pollutes context with irrelevant patterns. The agent then "remembers" things it shouldn't, and confidently introduces antipatterns "consistent with the rest of the file." Grep first. Range read. Always. This rule is the same on every tool because every tool has a context window.

### 6. Memory > rules for personal taste.

Rules in `core/universal-rules/*` are universal: every agent in every situation. Memory is per-user, accumulating taste. "User prefers terse responses with no trailing summaries" is a memory, not a rule. Saving it as a rule would burden every contributor's session in every project. Saving it as memory keeps the rules clean.

### 7. Honest about limits beats appearing complete.

CONDUCTOR will list, prominently, what each tool *cannot* do. Other multi-tool projects gloss over this and call it "abstract over differences." Glossing over it causes user pain three weeks in, when the abstraction breaks down. Honest documentation up front means users pick the right tool for the job knowingly.

### 8. Bilingual (한/영) is a first-class concern.

Korean solo developers are a meaningful early-adopter pool with high signal-to-noise. Most competitors are English-only. CONDUCTOR's `README.md`, marketing materials, and examples are bilingual; the universal-rules text is English-first for contributor accessibility but bilingual examples are welcome.

## What CONDUCTOR is NOT

- **Not a project manager.** No sprints, no story points, no retros. Just: Plan → Architecture → Tasks → Implementation → Review → Spec → Done.
- **Not a CI tool.** Hooks (where supported) run locally. CI integration is your project's job.
- **Not opinionated about your stack.** Templates use placeholders. Stack-specific rules live in your project's adapted output (e.g., `CLAUDE.md` for Claude users, `.cursorrules` for Cursor users).
- **Not a self-improving AI.** Memory accumulates only what you (or the orchestrator on your behalf) write. No silent learning. An opt-in Reflector may *propose* memory/rule deltas from session trajectories, but nothing is applied without human approval — proposing is not silent learning.
- **Not a replacement for your tool.** It sits on top of your tool. If your tool changes its rules format, the affected adapter changes; the universal layer doesn't.
- **Not enterprise software.** No SSO. No admin UI. No telemetry. No paid tier.

## When NOT to use CONDUCTOR

- **Tiny scripts** (< 50 lines, no real complexity). The overhead is wasteful.
- **Throwaway prototypes.** CONDUCTOR's discipline is for code that will be maintained.
- **Teams with established workflows** that contradict these patterns. Forcing CONDUCTOR onto a team mid-project causes friction.
- **You disagree with spec-as-you-go ABSOLUTE rule.** Don't use the framework; you'll fight it.

## When CONDUCTOR shines

- **Solo dev shipping production software** with one or more AI coding tools.
- **2-3 person team** that wants the same workflow across whatever AI tool each person uses.
- **Open source maintainer** who wants AI-using contributors to follow the same conventions.
- **Project lead trying to onboard a new contributor** quickly to a workflow that has earned its rules.

## Origin

CONDUCTOR was extracted from one year of internal use at LFamily Labs — a one-developer SaaS that grew to 10K+ lines with two-platform parity (web + mobile), 8-locale i18n, complex billing, and zero shipped regressions over six months. Every rule, hook, and agent in CONDUCTOR was earned through a real incident or near-miss. They are not theoretical best practices.

The v0.1 scaffold proved the rules work in Claude Code. The v0.2 multi-tool architecture exists because in 2026, no one uses just one AI coding tool — and rebuilding the discipline per tool is the friction killing adoption.
