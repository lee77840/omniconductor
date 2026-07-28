# Adapter Live-Verification Guide

> What the automated checks DO and DON'T cover, and a manual checklist to close the gap.

CONDUCTOR's CI + `tools/validate-adapter-output.sh` verify that each adapter **emits
the correct files** (right paths, the 5 universal rules present, no unsubstituted
placeholders, no reference-product leakage). Most tools still require an installed,
authenticated CLI and a real prompt to prove consumption. Codex additionally exposes
a local native prompt-input renderer, so its exact model-visible kernel can be checked
without sending repository content to a model. This guide covers that last mile.

Status legend: ✅ = automated (CI/validator) · 🧪 = needs a live session (this guide).

<!-- generated:live-verification-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Adapter | File emission | Live rule-loading |
|---|---|---|
| Claude Code | ✅ | ✅ **live-verified 2026-07-09** — 2.1.205 (Claude Code) headless probe listed 5/5 rules + read-CURRENT_WORK-first |
| Cursor | ✅ | 🧪 not yet run |
| Copilot | ✅ | 🧪 per-IDE — see docs/IDE-SMOKE-TESTING.md |
| Gemini CLI | ✅ | 🧪 not yet run |
| Codex | ✅ | ✅ **live-verified 2026-07-13** — codex-cli 0.144.0 native prompt-input probe confirmed bounded AGENTS kernel is model-visible; full references remain on demand |
| Windsurf | ✅ | 🧪 not yet run |
<!-- /generated:live-verification-table -->

> This table is generated from `adapters/<tool>/metadata.json` (`live_verification`) —
> `tools/live-verify.sh` updates the metadata after a successful live probe, and CI
> fails if the table and metadata disagree.

## Runtime compatibility contracts

Runtime compatibility is separate from file emission and live rule loading. Each
adapter declares product lineage, authentication uncertainty, policy gates, numeric
feature floors when a first-party or live-verified floor exists, and the type of probe
needed to establish effective activation. `omniconductor doctor` D13 reads this contract
and performs only a local `<cli> --version` inspection. CONDUCTOR has no authentication,
prompt, credential-file, network-client, or write path in this inspection. The child
receives only an execution-safe environment allowlist, and its raw output is never
surfaced in diagnostics. Since a provider CLI is external code, its internal
`--version` behavior is not treated as a portable sandbox guarantee.

<!-- generated:runtime-contract-table — edit adapters/*/metadata.json + run tools/generate-adapter-docs.js; do not hand-edit (ADR-042) -->
| Adapter | Product lifecycle | Auth contract | Applicable version floors | Probe contract |
|---|---|---|---|---|
| Claude Code | Claude Code · active | documented | posttool-output-rewrite ≥ 2.1.121 | headless-model; auth=yes, network=yes |
| Cursor | Cursor · active | policy-controlled | project-hooks ≥ 1.7.0<br>stop-followup-message ≥ 2.4.0 | headless-model; auth=yes, network=yes |
| Copilot | GitHub Copilot · active | policy-controlled | pretool-ask-decision ≥ 1.0.4 | headless-model; auth=yes, network=yes |
| Gemini CLI | Gemini CLI · source-conflict | source-conflict | native-hooks ≥ 0.26.0 | headless-model; auth=yes, network=yes |
| Codex | Codex · active | documented | no documented numeric floor | local-renderer; auth=no, network=no |
| Windsurf | Devin Desktop (adapter: Windsurf) · renamed | verification-required | no documented numeric floor | headless-model; auth=yes, network=yes |
<!-- /generated:runtime-contract-table -->

Statuses are deliberately observational:

- `not-installed` is informational: generated project files remain valid even when a
  developer does not have that tool on the current machine.
- `unsupported-version` means an installed runtime is below a floor applicable to an
  artifact CONDUCTOR actually emitted.
- `installed-unverified` means the CLI is visible but effective rule loading has not
  been recorded.
- `verification-required` covers first-party source conflicts or effective access that
  cannot be established offline.
- `product-migrated` records an intentional product rename while retaining the stable
  adapter identifier and legacy compatibility. It is emitted only after that renamed
  product line has a recorded live verification; a pending renamed CLI remains
  `installed-unverified`.
- `active` means the local runtime is visible, satisfies applicable floors, and has a
  recorded live verification. It does not override account or organization policy.

Gemini CLI is intentionally `source-conflict`: the 2026-06-18
[individual-account transition announcement](https://github.com/google-gemini/gemini-cli/discussions/28017)
states that individual traffic moved to Antigravity CLI, while the repository's current
[authentication guide](https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/authentication.mdx)
still documents individual Google-account login. CONDUCTOR records both dated sources
and requires an opt-in live result instead of guessing eligibility.

## Per-tool procedure

For each tool: (1) install into a throwaway project, (2) open the tool there, (3) run
the probe prompt, (4) record PASS/FAIL.

### Common setup
```bash
mkdir /tmp/cdt-<tool> && cd /tmp/cdt-<tool> && git init -q
bash <conductor>/adapters/<tool>/transform.sh . --no-prompt --recipes=coding-conventions
# (or: node <conductor>/bin/omniconductor.js init --target=<tool> . --no-prompt --recipes=coding-conventions)
```

### Probe prompt (same for every tool)
> "What workflow and rules are you operating under in this project? List the universal rules you can see, and tell me the first thing you must do before writing code."

**PASS criteria** — the tool's answer references CONDUCTOR's rules: the Plan-first /
spec-as-you-go / quality-gates discipline, and "read `docs/CURRENT_WORK.md` first" (or
equivalent). A generic answer that ignores the installed file = FAIL (tool didn't load it).

### Tool-specific load points
| Tool | File the tool must auto-load | Check |
|---|---|---|
| Gemini CLI | `GEMINI.md` (project root) + `.gemini/styleguide.md` | Does Gemini cite GEMINI.md content? Does it apply the styleguide on a code task? |
| Codex | bounded `AGENTS.md` kernel (project root) | Auto-probed locally by `tools/live-verify.sh` using `codex debug prompt-input`; requires the kernel end marker and rule routing |
| Windsurf / Devin Desktop | `.windsurfrules` + `.devin/rules/*.md` (legacy `.windsurf/rules/`) | Does Windsurf show the rules in its Rules panel? Does it follow them? |
| Claude Code | `CLAUDE.md` + `.claude/rules/*.md` + agents/hooks | Rules panel + a Stop-hook fires on a stale-docs commit |
| Cursor | `.cursor/rules/*.mdc` | Settings → Rules tab shows the 5 rules |
| Copilot | `.github/copilot-instructions.md` (or `.github/instructions/*`) | Per-IDE — see `docs/IDE-SMOKE-TESTING.md` |

### Recording results
Record each tool's outcome in `docs/COMPATIBILITY-MATRIX.md` (a "Live-verified" column):
`✅ verified <date>` / `⚠️ partial (note)` / `❌ tool ignored the file`.

A tool that emits correctly (CI green) but FAILS live-loading is a **documentation /
file-location** issue, not an emission bug — check the tool's current rules-file
convention (they change), update the adapter's output path, re-run CI, then re-test.

## Why this is separate from CI
Running every AI coding tool headlessly in CI is impractical (most need auth + a model).
Codex is the exception: its local `debug prompt-input` renderer verifies the exact
model-visible project instructions without sending repository content to a model.
So CONDUCTOR's CI guarantees *correct output*; live consumption is verified **locally**
by `tools/live-verify.sh` (ADR-043): it installs into a throwaway dir, probes the tool's
headless CLI with the prompt above, grades deterministically (>=3 of 5 rule names +
CURRENT_WORK — no LLM judge), and on PASS writes the result into
`adapters/<tool>/metadata.json`, regenerating the status table above. Tools whose CLI
is not installed are SKIPped honestly. Treat any 🧪 row as "emission-verified,
live-pending" until a probe (or a manual session per this guide) is recorded.

For a zero-network compatibility inspection, run:

```bash
bash tools/live-verify.sh --runtime-only
bash tools/live-verify.sh --runtime-only --tool=gemini
```

To exercise the authenticated/model-backed probe without changing metadata or generated
documentation, add `--check-only`. Omit it only when the result should become the
repository's recorded verification evidence:

```bash
bash tools/live-verify.sh --tool=claude --check-only
bash tools/live-verify.sh --tool=claude
```
