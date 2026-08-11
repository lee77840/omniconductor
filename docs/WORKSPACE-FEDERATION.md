# Read-only Multi-Repo Workspace

`omniconductor workspace doctor` validates a set of Git repositories as one change
context. It does not install adapters, checkout branches, update repositories, run an
agent, commit, push, or mutate the workspace manifest.

## Manifest

Create `.conductor/workspace.json` at a directory that contains the declared
repositories:

```json
{
  "schema_version": 1,
  "workspace_id": "product-suite",
  "repositories": [
    {
      "id": "shared",
      "path": "shared",
      "depends_on": [],
      "write_scopes": ["src"],
      "target_branch": "main",
      "required_adapters": ["codex"]
    },
    {
      "id": "frontend",
      "path": "frontend",
      "depends_on": ["shared"],
      "write_scopes": ["src", "tests"],
      "target_branch": "main",
      "required_adapters": ["codex", "cursor"]
    }
  ]
}
```

Repository paths and write scopes are relative and may not escape the workspace.
Every repository path must be its exact Git top-level. Symlinked roots, hard-linked
manifests, duplicate canonical repositories, unknown fields, unknown adapters, and
dependency cycles fail closed.

## Doctor

```bash
omniconductor workspace doctor /path/to/product-suite
omniconductor workspace doctor /path/to/product-suite --json
```

The report includes dependency order, branch, exact HEAD, clean/dirty state, adapter
manifest versions, missing required adapters, policy-version drift, and a deterministic
change-set digest covering every repository snapshot. Branch and policy-version drift
are warnings; unsafe paths, invalid schemas, missing required adapters, and non-Git or
nested repository declarations are failures.

This is deliberately a coordination view over independent project installs. Each
repository continues to own its own manifests, model routing, specs, and CURRENT_WORK.
