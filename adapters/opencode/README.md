# Adapter — OpenCode stable v1 (T2)

The OpenCode adapter installs CONDUCTOR without taking ownership of the root
`AGENTS.md`. That path may already belong to the Codex adapter. Instead it
semantically merges one bounded CONDUCTOR kernel into `opencode.json` and keeps
the OpenCode surface isolated under `.opencode/`.

Enumerable capability facts live in [`metadata.json`](./metadata.json). The full
boundary is in [`SUPPORTED-FEATURES.md`](./SUPPORTED-FEATURES.md).

## Install

Run this from the project you want OpenCode to work on:

```bash
npx omniconductor@latest init --target=opencode .
npx omniconductor@latest doctor .
```

Or invoke a checked-out adapter. The wrapper still enters the same Node CLI and
project-saved Tier-model transaction:

```bash
bash /path/to/conductor/adapters/opencode/transform.sh /path/to/project
```

For unattended installation, make model acceptance explicit:

```bash
npx omniconductor@latest init --target=opencode . \
  --no-prompt --accept-model-defaults
```

## Emitted surfaces

```text
opencode.json                              # semantic instructions merge
.opencode/rules/conductor-kernel.md        # bounded always-active kernel
.opencode/conductor/rules/*.md             # five complete on-demand rules
.opencode/conductor/recipes/*.md           # selected complete on-demand recipes
.opencode/rules/recipes/*.md               # compact pointers in recipes-only modes
.opencode/agents/*.md                      # eight baseline subagents
.opencode/plugins/conductor-guards.js      # v1 commit preconditions
.opencode/skills/*/SKILL.md                # portable skills
.opencode/commands/reflect.md              # recipe-gated manual Reflector
docs/*                                     # shared project-state templates
.conductor/manifests/opencode.json         # reversible ownership record
```

The adapter deliberately emits neither `AGENTS.md` nor `.agents/skills`. OpenCode
uses its own native `.opencode/skills` root, while the Codex adapter can continue to
own `AGENTS.md` in the same repository.

## Safety and compatibility

- Existing regular `opencode.json` is schema-merged and restored byte-for-byte on
  uninstall when it remains CONDUCTOR-owned.
- Existing `opencode.jsonc` fails during preflight before model routing or any
  managed output. CONDUCTOR will not erase comments or create a competing JSON file.
- Full and strict modes emit a project-local OpenCode v1 plugin for the two verified
  commit guards. Review-before-stop remains rule fallback because stable v1 exposes
  no verified continuation/deny contract for session completion.
- The adapter supports stable OpenCode v1. OpenCode v2 beta uses a breaking plugin
  contract and is not claimed compatible.
- The optional Reflector is propose-only on OpenCode: `/reflect` or the
  `reflect` skill can analyze available project evidence, but CONDUCTOR does not
  claim automatic OpenCode trajectory capture.

## Verify and remove

```bash
npx omniconductor@latest doctor .
npx omniconductor@latest init --target=opencode . --uninstall
```

`doctor` distinguishes emitted/validated state from authenticated live loading.
OpenCode provider authentication and model availability remain OpenCode policy.
