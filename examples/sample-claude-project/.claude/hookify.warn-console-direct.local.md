---
name: warn-console-direct
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: apps/.*\.(ts|tsx)$
  - field: new_text
    operator: regex_match
    pattern: console\.(error|log|warn)\s*\(
---

⚠️ **Direct `console.error/log/warn` call — use the project's logger helper**

Production code added a direct `console.*` call. The framework's coding-conventions recipe (`core/recipes/coding-conventions.md`) prefers a centralized logger helper over raw console for several reasons:

### Why a logger helper

- **Observability**: production logs route to an error-aggregation service automatically.
- **Context**: helper attaches contextual metadata (user ID, request ID, trace ID) the raw console drops.
- **Log level discipline**: error / warn / info / debug routed differently per environment.
- **PII safety**: client `console.*` is visible to users; helper can mask sensitive fields.

### Standard pattern

```ts
// ❌ Avoid in production code
catch (e) {
  console.error('Failed:', e)
  return { error: 'Failed' }
}

// ✅ Use the project logger
import { logError } from '<project>/lib/utils/errorLogger'

catch (e) {
  logError('<scope>', e, { userId, contextId })
  return { data: null, error: 'Failed' }
}
```

### Exemptions

- Test / spec files (most projects exclude `*.test.{ts,tsx}` and `*.spec.{ts,tsx}` from the file_path regex).
- Build / CLI scripts under `scripts/` — direct stdout is the contract.
- Server-side runtime where stdout *is* the log channel (e.g., serverless functions where stdout → platform log aggregator).

The default `apps/.*\.(ts|tsx)$` already excludes test files via the recommended pattern. Adjust if your project organizes tests differently.

### Project-local note

If your project does NOT have a logger helper module, this rule should be paired with introducing one (see `core/recipes/coding-conventions.md` "Error Handling"). Without the helper, the rule is just noise.

**Warn-only — operation proceeds.**
