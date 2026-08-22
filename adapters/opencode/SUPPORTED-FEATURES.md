# OpenCode stable v1 — supported features

This table separates OpenCode's native capability from what CONDUCTOR actually emits.
It covers stable v1 only; OpenCode v2 beta is unsupported until its breaking plugin
API receives a separate adapter contract.

| Feature | Status | CONDUCTOR mechanism / boundary |
|---|---|---|
| Always-loaded project rules | Native, emitted | `opencode.json` registers only `.opencode/rules/conductor-kernel.md`. Complete rules remain under `.opencode/conductor/rules/` for explicit Read routing. CONDUCTOR does not own root `AGENTS.md`. |
| Selected recipes | Native, opt-in | Full installs route from the bounded kernel to `.opencode/conductor/recipes/`; recipes-only modes register compact `.opencode/rules/recipes/*.md` pointers. |
| Named subagents | Native, emitted | Eight `.opencode/agents/*.md` profiles use `mode: subagent` and saved `provider/model` Tier translations. |
| Read-only review roles | Native, emitted | `planner`, `reviewer`, and `code-reviewer` deny `edit` and `bash` through current `permission` frontmatter. |
| Agent Skills | Native, emitted | `.opencode/skills/*/SKILL.md`; automatic discovery and explicit invocation follow OpenCode's skill contract. |
| Custom command | Native, recipe-gated | `.opencode/commands/reflect.md` is emitted only with `self-improvement`. |
| Commit CURRENT_WORK guard | Native v1 plugin | `tool.execute.before` checks staged files and blocks the matching Bash `git commit` call by throwing. |
| Commit test-evidence guard | Native v1 plugin | Same plugin rejects staged source changes without staged tests/evidence. |
| Review-before-stop | Rule fallback | Stable v1 has session events but no verified stop-continuation decision contract. CONDUCTOR does not inject a looping prompt. |
| Reflector | Manual/propose-only | `/reflect`, skill, agent, and local runner assets are emitted. Automatic OpenCode transcript capture is not claimed. |
| Model routing | Native field, provider-controlled | Agent `model` uses `provider/model`; provider access and administrator policy can still override availability. |
| Tool-output store-time cap | Not claimed | No verified v1 contract lets this adapter rewrite every tool result before storage. |
| MCP/extension audit | Read-only | `omniconductor audit extensions --target=opencode` inspects bounded project-local config without executing plugins or returning secret values. |
| Provider package | Direct fallback | Use `npx omniconductor init`; the optional package preview excludes executable guard plugins and does not invent an OpenCode marketplace manifest. |

## Config ownership

`opencode.json` and `opencode.jsonc` are competing project configuration surfaces.
CONDUCTOR supports a regular, non-linked JSON object and preserves unrelated keys and
instruction entries. If JSONC exists, installation fails before writes because a
comment-preserving merge is not implemented. Symlinks, hardlinks, traversal, and
foreign manifest paths fail closed through the shared path/manifest policy.

## Coexistence with Codex

OpenCode can natively read a root `AGENTS.md`, but this adapter never creates or owns
it. When Codex is also installed, OpenCode may observe both Codex's same-origin root
instructions and its own bounded `.opencode/rules/conductor-kernel.md`. The ownership ledger remains
conflict-free and uninstall stays adapter-scoped.

## Native guard concurrency caveat

The v1 documented deny mechanism is throwing from `tool.execute.before`. The plugin
narrows this to Bash commands that actually invoke `git commit`, executes only
read-only `git diff --cached`, and stores no prompt, response, command payload, or
credentials. An upstream report indicates plugin rejection may affect unrelated
parallel sessions in some versions, so this is a known OpenCode runtime risk rather
than a CONDUCTOR guarantee of per-session isolation.

## Verification levels

- Install, validator, doctor, uninstall, package-consumer, config round-trip, native
  plugin positive/negative, model-routing, and seven-adapter coexistence are local
  release gates.
- `opencode debug config` can prove local config/agent/plugin discovery without a
  model request.
- `opencode run` is the authenticated live rule-loading probe. Metadata remains
  `pending` unless that exact probe passes; file emission alone never upgrades it.
