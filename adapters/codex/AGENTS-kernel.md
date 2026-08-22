## Codex native appendix

`AGENTS.md` is the bounded always-loaded kernel. Complete text under
`.codex/conductor/` is reference material and must be read only when the routing
table or selected recipe applies.

`.codex/hooks.json` contains only verified Codex `PreToolUse` and `Stop`
contracts. Run `/hooks`, inspect the definitions, and explicitly trust them after
installation or modification. Hooks are deterministic guardrails, not a security
boundary, and do not intercept every equivalent tool path.

Before role dispatch, `.conductor/model-routing.json` must contain a Codex Tier
1/2/3 mapping. If absent, pause dispatch and ask the user to run
`npx omniconductor models configure --target=codex .`; never invent or silently
downgrade a model. Agent profiles compile the invariant Tiers to the saved model
and high/medium/low reasoning effort.
