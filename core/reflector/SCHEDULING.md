# Scheduling the weekly Reflector

The Reflector is **propose-only** — a scheduled run reads `.conductor/trajectories/index.jsonl`
+ git history and appends proposals to `docs/REFLECTION-PROPOSALS.md`. It applies nothing.
Nothing here auto-registers a schedule (that is a machine/user-level action a repo installer
cannot do for you); this documents how to register the runner CONDUCTOR emitted:

    .conductor/reflect/run-weekly.sh

It auto-detects the first supported CLI on `PATH`
(`claude` → `codex` → `gemini` → `cursor-agent` → `copilot` → `devin`).
Force one with `CONDUCTOR_REFLECT_CLI=<cli>`; preview with `CONDUCTOR_REFLECT_DRYRUN=1`.

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
    - run: npm i -g @github/copilot && copilot -p "$(cat .conductor/reflect/reflect-brief.md)" --allow-tool=write --no-ask-user
      env: { COPILOT_GITHUB_TOKEN: ${{ secrets.PERSONAL_ACCESS_TOKEN }} }

(Trigger with `on: { schedule: [{ cron: "0 9 * * 1" }] }`.)

## After a run

Review `docs/REFLECTION-PROPOSALS.md`; for accepted deltas, add them as `feedback_lesson-*.md`
memory entries, then run `.conductor/reflect/prune-lessons.sh <memory-dir>` to keep the set bounded.

---

*Headless flags + scheduler local/cloud behavior verified against first-party docs 2026-07-05.
Some details (Cursor custom-command in `-p`, exact approval-flag names, Copilot-app local file
scope, the Copilot CI token env var `COPILOT_GITHUB_TOKEN`) were not first-party-confirmable —
the runner inlines the brief text rather than relying on unverified `/reflect` resolution, and
you may need to add your tool's write-approval flag / confirm its CI secret name.*
