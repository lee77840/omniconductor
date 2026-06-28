# Adapter — GitHub Copilot (T2)

GitHub Copilot is a T2 target because:

- It supports per-pattern rule scoping via `.github/instructions/*.instructions.md` `applyTo:` front-matter.
- Instructions live IN the repo, so all collaborators automatically share them.
- Copilot's PR review feature provides a partial Stage B code-review analog tied to GitHub.

It is **T2 (not T1)** because:

- ❌ No sub-agent dispatch.
- ❌ No hooks for ABSOLUTE enforcement.
- ❌ No per-call model routing (model picker in UI).
- ❌ No built-in memory directory.
- ⚠️ Slash commands limited.

**Tier**: T2 — Good support; rule scoping works well, enforcement is limited.

## Installation path

```bash
# Install (the copilot adapter is implemented):
bash /path/to/conductor/adapters/copilot/transform.sh /path/to/target [--dry-run]

# (planned / roadmap — not yet available):
# npx omniconductor init --target=copilot [target-dir]
```

## What gets installed

```
<target>/
├── .github/
│   └── instructions/
│       ├── all.instructions.md                 # applyTo: '**' (always-loaded)
│       ├── operations.instructions.md          # applyTo: '**'
│       ├── coding-conventions.instructions.md  # applyTo: '**/*.{ts,tsx,js,jsx}'
│       ├── token-economy.instructions.md       # applyTo: '**'
│       ├── spec-as-you-go.instructions.md      # applyTo: 'docs/specs/**,**/*.md'
│       └── model-routing.instructions.md       # applyTo: '**'
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Native features supported

- ✅ Always-loaded baseline (`applyTo: '**'`).
- ✅ Per-pattern rule scoping (`applyTo:` front-matter).
- ✅ Instructions IN the repo (collaborator-shared).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ⚠️ Copilot PR review feature for Stage B (partial).

## Features NOT supported

| Feature | Workaround |
|---|---|
| Sub-agent dispatch | Human plays orchestrator role. |
| Hooks | Pair with project-level pre-commit git hooks for enforcement. |
| Per-call model routing | Pick model in Copilot Chat UI. |
| Built-in memory directory | DIY at `.memory/` (gitignored). |
| Specialized review agents (Stage A) | Run review prompts manually in Copilot Chat. Use Copilot PR review for Stage B (best-effort). |

## After install — first steps

1. Commit `.github/instructions/` to your repo. All collaborators automatically pick up the rules.
2. Configure Copilot PR review for Stage B (in repo settings).
3. Customize the always-loaded section of `all.instructions.md` — replace `{{PROJECT_NAME}}`.
4. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md`.
5. Add `.memory/` to `.gitignore`. Create your first memory entry.

## Quirks / known issues (P3 will fill)

- TBD: Copilot's `applyTo:` glob syntax differs slightly from Cursor's `globs:`. P3 verifies the exact dialect.
- TBD: Copilot Chat's instruction-loading order when multiple files match.

## Status (P0 foundation)

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
- ⏳ `notes.md` (P3)
