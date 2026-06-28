# IDE Smoke Testing — Conductor adapter outputs

> Per-IDE manual verification checklist for Conductor's `cursor` and `copilot` adapter outputs.
>
> **Why this exists**: orchestrator (Mac + bash + Claude Code) cannot drive 6 IDEs directly. Adapter `transform.sh` is smoke-tested against synthetic targets and a format validator (`tools/validate-adapter-output.sh`), but the *real* question — does the IDE actually load the rules and feed them to the AI assistant — must be answered by humans opening the IDE.
>
> **How to use**: pick an IDE you have installed. Walk the steps. Record PASS/FAIL per step. Report results back into `docs/COMPATIBILITY-MATRIX.md`'s "Per-IDE smoke" column.
>
> **Goal**: 6/7 PASS for any IDE = we mark that IDE "Empirically Verified" in the matrix. Below 6/7 = open an issue with quirks documented.

---

## Common pre-requisites (all IDEs)

1. Conductor repo cloned locally (we'll run adapter from here).
2. A test project (≥ 1 source file). Recommendation: a fresh `/tmp/conductor-smoke-<ide>` directory with one or two `.ts` / `.py` files.
3. Internet connectivity (for AI assistant calls).
4. Adapter pre-flight: run `bash tools/validate-adapter-output.sh <test-target> <adapter>` and confirm exit 0 BEFORE opening the IDE. If validator fails, fix the format issue first — IDE load is guaranteed to fail too.

PASS criteria across all sections: a step "PASSes" when the observable evidence matches expectation. If you can't tell, mark it INCONCLUSIVE — that's a doc gap to file separately.

---

## 1. Cursor (native `.cursor/rules/*.mdc`)

### Pre-requisite

- Cursor installed, logged in (https://cursor.com).
- Cursor version with `.cursor/rules/*.mdc` support (any modern build, late-2025 onward).

### Setup

```bash
mkdir -p /tmp/conductor-smoke-cursor
echo "function hello() { return 'world'; }" > /tmp/conductor-smoke-cursor/test.ts
cd <conductor-repo>
bash adapters/cursor/transform.sh /tmp/conductor-smoke-cursor --no-prompt
bash tools/validate-adapter-output.sh /tmp/conductor-smoke-cursor cursor
# Expect: exit 0, PASS for all .mdc
```

### Smoke steps

| # | Step | Expected evidence |
|---|---|---|
| 1 | Open `/tmp/conductor-smoke-cursor` in Cursor (`File → Open Folder`). | Project tree shows `.cursor/rules/`, `docs/`, `test.ts`. |
| 2 | Open Cursor settings → "Rules" panel (or `Cmd/Ctrl+Shift+P` → `Cursor: Show Rules`). | All 5 universal rules listed: workflow, operations, quality-gates, spec-as-you-go, meta-discipline. |
| 3 | Open `test.ts`. Open Cursor chat. Type: "What rules apply to this file?" | Cursor mentions at least one rule by name (most reliably: `workflow.mdc` or `operations.mdc` since they're `alwaysApply: true`). |
| 4 | In chat, ask: "Add a TODO comment to this file." Observe whether the response respects spec-as-you-go (prompts about updating docs). | If the rule loaded correctly, Cursor's response references `docs/specs/` or "spec-as-you-go" terminology. Pure code edit with no doc mention = rule not loaded. |
| 5 | Edit `.cursor/rules/workflow.mdc` (e.g., add a sentinel string `// CONDUCTOR-SMOKE-MARKER`). Reload Cursor window (`Cmd/Ctrl+Shift+P` → `Developer: Reload Window`). Open chat. | New chat session: Cursor's behavior reflects the edit (e.g., the marker shows up if you ask "what's in your workflow rule"). |
| 6 | Toggle the rule off (Settings → Rules → uncheck workflow). Open new chat, ask same question as step 3. | Workflow rule no longer appears in the response or rules list. |
| 7 | Re-enable the rule. Confirm it reappears. | Rule listed again; behavior reverts. |

### Known quirks

- See `docs/IDE-COMPATIBILITY-NOTES.md` § Cursor.
- `globs:` array form (multiline `- "*.ts"` etc.) supported; inline JSON-array form (`globs: ["*.ts"]`) supported in late-2025 builds. If on an older build, validator may PASS but Cursor may not load — fall back to single-string `globs:` form.

### PASS criteria

- 6/7 steps PASS = SHIPPED for Cursor.
- Step 4 INCONCLUSIVE alone = still SHIPPED (rule loaded; AI behavior is non-deterministic).
- Step 2 FAIL = adapter output format mismatch; re-run validator with verbose, file an adapter bug.

### FAIL recovery

| Failed step | Likely cause | Fix |
|---|---|---|
| 2 | `.cursor/rules/` not detected | Cursor too old; upgrade. Or: `globs:` malformed (validator should have caught — file a validator-gap issue). |
| 3 | Rules not surfacing in chat | Reload window. If still failing: check `alwaysApply: true` is set on workflow.mdc. |
| 5 | Edit not picked up | Reload didn't take; quit Cursor entirely and reopen. |

---

## 2. VS Code + GitHub Copilot extension

### Pre-requisite

- VS Code installed.
- Copilot extension installed + signed in (https://marketplace.visualstudio.com/items?itemName=GitHub.copilot).
- Copilot Chat extension (`GitHub.copilot-chat`) — REQUIRED for `applyTo:` instructions to be honored.

### Setup

```bash
mkdir -p /tmp/conductor-smoke-vscode
echo "def hello(): return 'world'" > /tmp/conductor-smoke-vscode/test.py
cd <conductor-repo>
bash adapters/copilot/transform.sh /tmp/conductor-smoke-vscode --no-prompt --per-rule
bash tools/validate-adapter-output.sh /tmp/conductor-smoke-vscode copilot
```

### Smoke steps

| # | Step | Expected evidence |
|---|---|---|
| 1 | Open `/tmp/conductor-smoke-vscode` in VS Code. | Project tree shows `.github/copilot-instructions.md` AND `.github/instructions/*.instructions.md`. |
| 2 | Open Copilot Chat panel (`Cmd/Ctrl+Alt+I`). Look for "Used N references" footer on first response. | Copilot Chat shows `.github/copilot-instructions.md` referenced. |
| 3 | Open `test.py`. In chat, ask: "What instructions apply when editing this file?" | Copilot mentions `workflow`, `quality-gates`, or other instruction file by name (since they have `applyTo: '**'` they should ALL match). |
| 4 | Ask: "Refactor this function to add a docstring." | Response should reference Conductor's "spec-as-you-go" rule (mention `docs/specs/`). Pure code edit = rule not surfaced. |
| 5 | Edit `.github/instructions/workflow.instructions.md`: add a sentinel comment. No reload needed in VS Code (Copilot reads on next request). Ask Copilot a fresh question. | New behavior reflects the edit. |
| 6 | Test Copilot **completion** (not chat): position cursor in `test.py`, start typing a function. | NOTE: Completion side does NOT honor `.github/instructions/*.instructions.md` reliably. Mark INCONCLUSIVE unless you see clear evidence. Only chat is verified. |
| 7 | Open `test.py` and rename to `test.ts`. Ask Copilot Chat the same question as step 3. | Same instruction list (we use `applyTo: '**'`). If we used scoped applyTo, behavior would change here. |

### Known quirks

- See `docs/IDE-COMPATIBILITY-NOTES.md` § Copilot.
- Copilot **Completion** mostly ignores `.github/instructions/*.instructions.md`; only Copilot **Chat** reliably consumes them.
- `applyTo:` MUST be a quoted CSV string (`'**'` or `'src/**,docs/**'`). YAML arrays cause silent rejection — validator catches this.

### PASS criteria

- 5/7 PASS = SHIPPED for VS Code + Copilot (step 6 typically INCONCLUSIVE; step 7 is a no-op when applyTo is `**`).
- Steps 1-4 PASS is the minimum viable result.

### FAIL recovery

| Failed step | Likely cause | Fix |
|---|---|---|
| 2 | "Used N references" footer absent | Copilot Chat extension not installed. Install `GitHub.copilot-chat`. |
| 3 | No instruction names mentioned | Confirm `.github/copilot-instructions.md` exists; restart VS Code window. |
| 4 | spec-as-you-go not surfaced | Open `.github/instructions/spec-as-you-go.instructions.md`; verify body intact. |

---

## 3. Cursor + GitHub Copilot extension (dual-stack)

Cursor accepts the Copilot extension. Adopters in this dual-stack mode want both `.cursor/rules/` (native) AND `.github/copilot-instructions.md` (Copilot-side) to load.

### Pre-requisite

- Cursor (per § 1).
- Copilot extension installed in Cursor.

### Setup

```bash
mkdir -p /tmp/conductor-smoke-cursor-copilot
cd <conductor-repo>
bash adapters/cursor/transform.sh /tmp/conductor-smoke-cursor-copilot --no-prompt
bash adapters/copilot/transform.sh /tmp/conductor-smoke-cursor-copilot --no-prompt --per-rule
bash tools/validate-adapter-output.sh /tmp/conductor-smoke-cursor-copilot cursor
bash tools/validate-adapter-output.sh /tmp/conductor-smoke-cursor-copilot copilot
```

### Smoke steps

| # | Step | Expected evidence |
|---|---|---|
| 1 | Open project in Cursor. Verify both `.cursor/rules/` AND `.github/instructions/` exist. | Both directories populated. |
| 2 | Open Cursor's native chat (default). Ask "What rules apply?". | Cursor lists its own `.mdc` rules (NOT `.github/instructions/`). |
| 3 | Switch to Copilot Chat extension (sidebar icon, separate from native chat). Ask same question. | Copilot Chat lists `.github/instructions/*` files. |
| 4 | Verify the two channels do NOT conflict (one chat doesn't show the other's rules). | Both panels distinct. |
| 5 | Ask Cursor's native chat to refactor `test.ts`. | Response respects Cursor `.mdc` rules (spec-as-you-go reference). |
| 6 | Ask Copilot Chat the same. | Response respects Copilot `.instructions.md` rules. |
| 7 | Disable native Cursor rules (Settings → Rules → uncheck all). Native chat now lacks rules; Copilot chat retains its own. | Confirms isolation between rule channels. |

### Known quirks

- Adopters running both cost: 2× rule storage in repo (`.cursor/rules/` + `.github/instructions/`). Documented intentional duplication.

### PASS criteria

- 6/7 PASS.
- Critical: step 4 (no cross-contamination) MUST pass.

---

## 4. Windsurf

Windsurf (Codeium) ships a Copilot adapter that reads `.github/copilot-instructions.md`. Native Codeium rules use a separate format (`.windsurfrules`) — Conductor's Copilot adapter does NOT produce this; only the Copilot-side files.

### Pre-requisite

- Windsurf installed (https://codeium.com/windsurf).
- Logged in.

### Setup

```bash
mkdir -p /tmp/conductor-smoke-windsurf
cd <conductor-repo>
bash adapters/copilot/transform.sh /tmp/conductor-smoke-windsurf --no-prompt --per-rule
```

### Smoke steps

| # | Step | Expected evidence |
|---|---|---|
| 1 | Open project in Windsurf. | Project tree visible. |
| 2 | Open Cascade chat panel. Ask "What rules apply?". | Cascade mentions `.github/copilot-instructions.md` content (or its substantive rules). |
| 3 | Open `test.py`. Ask Cascade for a refactor. | Response respects spec-as-you-go (mentions docs sync). |
| 4 | Open `.github/instructions/workflow.instructions.md`. Edit + save. Ask Cascade a fresh question. | Edit reflected (Windsurf re-reads on each request). |
| 5 | Test Codeium **completion**. | Completion likely ignores the instructions (similar to Copilot Completion). Mark INCONCLUSIVE. |
| 6 | Confirm Windsurf does NOT auto-create `.windsurfrules` from Conductor output. | Conductor doesn't produce it; manual conversion required if Windsurf-native scoping is needed. |
| 7 | Disable Codeium temporarily; confirm Cascade no longer responds. | Sanity check — extension wiring intact. |

### Known quirks

- Windsurf Cascade chat reads `.github/copilot-instructions.md`; per-file `.github/instructions/*.instructions.md` support is undocumented (treat as bonus, not guarantee).
- Native Windsurf rules in `.windsurfrules` is a separate Conductor adapter (P3.5 deferred).

### PASS criteria

- 4/7 PASS = "Empirically verified for Cascade chat".
- Step 5 INCONCLUSIVE accepted.
- Steps 4 + 6 PASS confirms Conductor's adapter contract holds.

---

## 5. JetBrains family (IntelliJ, WebStorm, PyCharm, etc.) + Copilot plugin

### Pre-requisite

- A JetBrains IDE 2024.3+ (older versions have flaky Copilot plugin).
- "GitHub Copilot" plugin installed (Settings → Plugins → search "GitHub Copilot").
- Logged in.

### Setup

```bash
mkdir -p /tmp/conductor-smoke-jetbrains
cd <conductor-repo>
bash adapters/copilot/transform.sh /tmp/conductor-smoke-jetbrains --no-prompt --per-rule
```

### Smoke steps

| # | Step | Expected evidence |
|---|---|---|
| 1 | Open project in JetBrains IDE. | Project tree shows `.github/`. |
| 2 | Open Copilot Chat (right sidebar, Copilot icon). | Panel opens; chat ready. |
| 3 | Ask "What instructions apply?". | Copilot mentions `.github/copilot-instructions.md` (top-level bundle). Per-file `.github/instructions/*.instructions.md` support depends on plugin version. |
| 4 | Ask for a refactor on a `.py`/`.kt` file. | Response respects spec-as-you-go. |
| 5 | Edit instruction file; ask new question. | Edit reflected. |
| 6 | Test Copilot Completion (start typing a function). | Completion ignores instructions (typical). INCONCLUSIVE. |
| 7 | Verify plugin reads from project root, not IDE-global location. | Confirms project-scoped rules. |

### Known quirks

- JetBrains Copilot plugin pre-2024.3 has unreliable instruction support. Insist on 2024.3+.
- Recent plugin builds (post-2025-Q4) added `.instructions.md` per-file support; older builds only read top-level.

### PASS criteria

- 5/7 PASS = SHIPPED.
- Step 3 partial (top-level only, no per-file) = still acceptable; flag plugin version.

---

## 6. Neovim + copilot.vim

### Pre-requisite

- Neovim 0.9+.
- `copilot.vim` (or `copilot.lua`) installed.
- Optional: `CopilotChat.nvim` for chat (otherwise only completion is available).

### Setup

```bash
mkdir -p /tmp/conductor-smoke-nvim
cd <conductor-repo>
bash adapters/copilot/transform.sh /tmp/conductor-smoke-nvim --no-prompt --per-rule
```

### Smoke steps

| # | Step | Expected evidence |
|---|---|---|
| 1 | `cd /tmp/conductor-smoke-nvim && nvim test.py`. | File opens; Copilot status shows "ready". |
| 2 | If `CopilotChat.nvim` installed: `:CopilotChat what rules apply?`. | Chat references `.github/copilot-instructions.md`. |
| 3 | If chat NOT installed: skip 2 and 4; only completion is testable (and known to ignore instructions). | INCONCLUSIVE for completion-only setups. |
| 4 | Ask CopilotChat for a refactor. | Spec-as-you-go surfaced. |
| 5 | Edit instruction file. New question. | Edit reflected. |
| 6 | Test completion (in insert mode, suggestions). | Completion likely IGNORES instructions. INCONCLUSIVE. |
| 7 | Confirm Neovim is reading the same `.github/copilot-instructions.md` (no IDE-global override). | Confirmed by step 2. |

### Known quirks

- `copilot.vim` completion side has zero documented support for instructions.
- `CopilotChat.nvim` is a community plugin; instructions support tracks the upstream Copilot Chat protocol but lags VS Code by a few weeks.

### PASS criteria

- 3/7 PASS (steps 2, 4, 5 if chat installed) = SHIPPED for chat-side.
- Completion-only adopters: this IDE is rated "BASIC" — discipline self-policed; Conductor rules visible only by reading the files manually.

---

## Reporting results

After running smoke tests for one IDE:

1. Paste your PASS/FAIL grid into a new GitHub issue titled `[smoke] <IDE name> <date>`.
2. Update `docs/COMPATIBILITY-MATRIX.md` "Per-IDE smoke" column for that row from `pending` → `<N>/7 (date)`.
3. If any step revealed a new quirk, append a bullet to `docs/IDE-COMPATIBILITY-NOTES.md` under the IDE's section.

## Validator-only mode (no IDE access)

If you can't run the IDE but want to validate adapter outputs in CI / automation:

```bash
bash tools/validate-adapter-output.sh <target> <adapter>
```

Exit 0 = format conforms. This catches frontmatter errors, missing fields, broken markdown — the most common adapter bugs. It does NOT prove the IDE consumes the file (that requires manual smoke).
