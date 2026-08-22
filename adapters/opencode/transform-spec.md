# OpenCode stable v1 adapter transform specification

## Input

- Read canonical rule, recipe, role, skill, document, and Reflector assets from
  `core/` without modifying them.
- Receive a target directory plus the shared `--mode`, `--recipes`, `--dry-run`,
  `--no-prompt`, `--uninstall`, and `--force` options through the main CLI.
- Require project-saved OpenCode Tier 1/2/3 values in `provider/model` form before
  role-emitting writes. Recipes-only remains model-independent.

## Preflight and conflicts

1. Resolve the real target and pass shared path-safety checks.
2. Refuse linked/hard-linked/special managed paths and unsafe manifests.
3. Parse regular `opencode.json` as a JSON object and require `instructions` to be an
   array when present.
4. If `opencode.jsonc` exists, fail before model routing or any managed output. Do not
   create a competing JSON file and do not erase comments.
5. Strict mode refuses existing config, rules, or conflicting portable skills.

## Output

- Semantically merge only the bounded kernel into `opencode.json.instructions` in
  full/strict/minimal modes; recipes-only modes register compact recipe pointers.
  Retain unrelated keys and entries.
- Emit five byte-identical complete universal-rule references and selected complete
  recipe references outside the always-active instruction surface.
- In full/strict mode emit eight `.opencode/agents/*.md` subagents with saved models.
  Planner, reviewer, and code-reviewer deny `edit` and `bash` through current
  `permission` frontmatter.
- In full/strict mode emit `.opencode/plugins/conductor-guards.js`, implementing only
  the two registry-approved commit guards through `tool.execute.before`.
- Emit native `.opencode/skills`; self-improvement additionally emits the manual
  propose-only Reflector command, skill, agent, and local runner assets.
- Never emit root `AGENTS.md` and never claim OpenCode v2 beta compatibility,
  review-stop continuation, automatic trajectory capture, or store-time output cap.
- Record every managed file in `.conductor/manifests/opencode.json` with the shared
  checksum/backup/ownership contract.

## Lifecycle invariants

- Dry-run is byte- and path-zero-write.
- Reinstall is idempotent and preserves unrelated project config.
- Uninstall restores the original config bytes when unmodified, preserves adopter
  edits, removes unchanged emitted files, prunes empty managed directories, and keeps
  project-saved model routing.
- OpenCode and Codex can coexist because their adapter-owned paths do not overlap.

## Required verification

- Five install modes, config merge/restore, JSONC preflight, guard positive/negative,
  model routing, path safety, validator, doctor, metadata M1-M15, generated docs,
  seven-tool coexistence/uninstall, package consumer, published-version upgrade, and
  exact public snapshot.
- `opencode debug config`, `opencode debug agent`, and `opencode debug skill` prove
  local runtime discovery without a model call.
- Only a successful deterministic `opencode run` probe may mark live rule loading
  verified.
