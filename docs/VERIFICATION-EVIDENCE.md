# Verification Evidence Contract

CONDUCTOR evidence schema v1 prevents a skipped, blocked, environment-limited, or
unproven check from being flattened into PASS. The contract is provider-neutral and
read-only: validation does not execute commands, open artifact references, contact a
service, or modify the project.

## Commands

```bash
# Schema validity only. A valid report may still contain unresolved claims.
npx omniconductor evidence validate verification-evidence.json

# Exit 0 only when every valid claim is passed; exit 1 for a valid incomplete gate.
npx omniconductor evidence check verification-evidence.json
```

Both commands return exit 2 for malformed/unsafe input or schema violations. Input
must be a single-link regular JSON file no larger than 1 MiB. `--json` returns only the
report path and aggregate counts; it does not echo claim content, commands, or evidence
references that may contain sensitive project metadata.

## Schema v1

```json
{
  "schema_version": 1,
  "snapshot": {
    "kind": "git-commit",
    "value": "0123456789abcdef0123456789abcdef01234567",
    "dirty": false
  },
  "claims": [
    {
      "id": "web.build",
      "claim": "The web build succeeds on the recorded commit.",
      "status": "passed",
      "reason": "The command exited zero.",
      "command": "npm run build:web",
      "evidence": [
        {
          "kind": "command",
          "ref": "CI job build-web, exit 0",
          "digest": "sha256:replace-with-real-digest"
        }
      ],
      "reproducible": true
    },
    {
      "id": "production.auth-e2e",
      "claim": "Production authentication completes end to end.",
      "status": "environment-limited",
      "reason": "The verification environment has no production test credential.",
      "evidence": [],
      "missing": ["authorized production test credential"],
      "reproducible": false
    }
  ]
}
```

Snapshot kinds are `git-commit`, `git-tree`, `content-digest`, or
`external-version`. Evidence kinds are `command`, `artifact`, `observation`, or
`external`. References are bounded pointers, not embedded logs, prompts, source files,
database rows, credentials, or chain-of-thought.

Git commit/tree identifiers use their full lowercase hex object ID. A dirty working
state cannot be identified by its base commit alone, so `dirty: true` is accepted only
with an algorithm-prefixed `content-digest` that covers every in-scope tracked,
untracked, and relevant generated input.

## Status semantics

| Status | Meaning |
|---|---|
| `passed` | Concrete evidence proves the named observable on the recorded snapshot. |
| `failed` | Concrete evidence contradicts the claim. |
| `blocked` | A required authority, dependency, or prerequisite prevents execution. |
| `not-run` | The check was not executed and the reason is explicit. |
| `environment-limited` | The available environment cannot represent the required environment. |
| `verification-required` | Implementation may exist, but sufficient proof is absent. |

A passed claim requires evidence and cannot declare a missing requirement. Every
unresolved status requires at least one `missing` entry. The contract intentionally
does not infer truth from a green build, file existence, a test name, an isolated
non-reproduction, or another snapshot's evidence.

## Recipe integration

- `database-change-assurance` binds intent, approval, pre/post-state, and rollback.
- `non-vacuous-testing` binds negative sensitivity and final positive evidence.
- `visual-baseline-integrity` binds the render contract and image-diff evidence.
- `web-mobile-parity` and `i18n` bind surface/locale matrix coverage.
- `release-provenance` binds source, authority, policy, and release artifact evidence.

The seven adapters emit the same recipe and `verify-change` instruction text. This CLI
contract is universal enforcement; provider-native hooks remain limited to the exact
capabilities declared in adapter metadata.
