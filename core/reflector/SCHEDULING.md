# Scheduling the weekly Reflector

The Reflector is **propose-only** — a scheduled run analyzes trajectories in a
verified read-only CLI mode. The model emits typed data; a trusted deterministic
writer alone appends `docs/REFLECTION-PROPOSALS.md`. It applies nothing.
Nothing here auto-registers a schedule (that is a machine/user-level action a repo installer
cannot do for you); this documents how to register the runner CONDUCTOR emitted:

    .conductor/reflect/run-weekly.sh

It auto-detects the first supported CLI on `PATH`
(`claude` → `codex` → `gemini` → `cursor-agent` → `copilot` → `opencode`).
Force one with `CONDUCTOR_REFLECT_CLI=<cli>`; preview with `CONDUCTOR_REFLECT_DRYRUN=1`.

## Bounded runner (Node.js 18+)

The runner uses the selected CLI's saved Tier 1 mapping from
`.conductor/model-routing.json`; it does not silently inherit a session model.
It reads at most 12 recent session metadata entries (14 days), 20 commit subjects,
and a 16 KiB active-state prefix, with a 32 KiB total evidence ceiling. It does not
follow arbitrary transcript pointers. Missing trajectories fall back to git/state;
no evidence means no model call. Manual deep reflection is a separate scoped task.

Identical evidence, model and brief skip the model call after a successful import.
The local watermark is `.conductor/reflect/last-success.json`. Failed/invalid runs
do not advance it. `run.lock` prevents overlapping runs; after an interrupted host,
confirm that no runner remains before removing a stale lock. These are local state,
not portable rules; deleting the watermark intentionally allows another analysis.

Execution defaults to 120 seconds (`CONDUCTOR_REFLECT_TIMEOUT_SECONDS=1..300`),
with at most 1 MiB captured output. These are local runner bounds, **not** provider
billing, hidden-context, or remote-job cancellation guarantees. Direct skill calls
and app automation prompts do not automatically inherit the runner's deduplication
or deadline: schedule this script to obtain those protections. A wiring dry-run
does not validate model availability or consume a paid smoke call.

Windsurf/Devin remains a manual `/reflect` workflow until its CLI exposes an
equivalent verified headless read-only contract. The runner fails closed rather
than granting broad workspace writes.

> **Local vs cloud — the one rule that matters.** The trajectory log lives locally under
> `.conductor/` (typically git-ignored). A **cloud** scheduler runs on a fresh clone and
> **cannot see it**. So for local-trajectory reflection, use a **local** scheduler:
> OS cron / launchd, Claude Desktop scheduled tasks, or Codex app automations.
> Cloud schedulers (Cursor Automations, Copilot cloud automations, Devin Scheduled Sessions)
> only work if you commit `.conductor/trajectories/` — not recommended.

## Universal: OS cron / launchd (works on every tool, local files)

`cron` — weekly, Mondays 09:00 (edit `crontab -e`), using an absolute project path:

    0 9 * * 1  cd /abs/path/to/project && ./.conductor/reflect/run-weekly.sh >> .conductor/reflect-weekly.log 2>&1

macOS `launchd` — a `~/Library/LaunchAgents/conductor-reflect.plist` `StartCalendarInterval`
entry (Weekday 1, Hour 9) invoking the same script. Dry-run first:

    CONDUCTOR_REFLECT_DRYRUN=1 ./.conductor/reflect/run-weekly.sh

## Native local schedulers (best where available)

- **Claude Code — Desktop Scheduled Tasks** (local; sees uncommitted files; weekly picker).
  Create a task whose prompt is `/reflect` (Desktop app must be open, machine awake). The
  cloud "Routines" run on a fresh clone → they will NOT see local trajectories.
- **Codex — app Automations** (local project, `cron` syntax, invokes saved skills). Create a
  weekly automation running the `$reflect` skill against the local project (Codex app must be
  running, project present on disk).

## Cloud schedulers — trajectory-blind (avoid for local reflection)

Cursor **Automations**, Copilot **cloud** automations, and Devin **Scheduled Sessions** run in a
cloud clone and cannot read un-committed `.conductor/`. Use OS cron locally instead. (Copilot's
desktop app also has *local* automations, which can work like the OS-cron path.)

## CI: GitHub Actions (cron) — only if trajectories are committed

A workflow runs on a fresh checkout, so `.conductor/trajectories/index.jsonl` must be committed
(or restored from an artifact), and the resulting `docs/REFLECTION-PROPOSALS.md` committed/PR'd
back. Per-tool official actions + `on: schedule`:

    # Claude
    - uses: actions/checkout@v4
    - uses: anthropics/claude-code-action@v1
      with: { prompt: "/reflect", anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }} }

    # Gemini
    - uses: google-github-actions/run-gemini-cli@v0
      with: { prompt: "/reflect", gemini_api_key: ${{ secrets.GEMINI_API_KEY }} }

    # Codex
    - uses: openai/codex-action@v1
      with: { prompt: "Run the $reflect skill", openai-api-key: ${{ secrets.OPENAI_API_KEY }} }

    # Copilot
    - run: npm i -g @github/copilot && .conductor/reflect/run-weekly.sh
      env: { COPILOT_GITHUB_TOKEN: ${{ secrets.PERSONAL_ACCESS_TOKEN }} }

(Trigger with `on: { schedule: [{ cron: "0 9 * * 1" }] }`.)

## After a run

Review `docs/REFLECTION-PROPOSALS.md`; for accepted deltas, add them as `feedback_lesson-*.md`
memory entries, then run `.conductor/reflect/prune-lessons.sh <memory-dir>` to keep the set bounded.

---

*Headless read-only flags were re-verified against first-party CLI contracts on
2026-08-13. Provider-native enforcement differs, but the invariant is the same:
the analyzer cannot write and the trusted importer owns the one proposal path.*
