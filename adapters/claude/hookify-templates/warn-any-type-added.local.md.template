---
name: warn-any-type-added
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.(ts|tsx)$
  - field: new_text
    operator: regex_match
    pattern: :\s*any\b
---

⚠️ **`: any` type added — TypeScript discipline (recipe `coding-conventions.md` ABSOLUTE)**

A TypeScript file gained a `: any` type annotation. The framework's coding-conventions recipe (`core/recipes/coding-conventions.md`) marks `any` as forbidden: it bypasses the type system the project pays to maintain.

### Alternatives

| Use case | Replacement |
|---|---|
| Unknown shape from external data | `unknown` + type guard / Zod schema |
| Temporary prototype | TODO comment + explicit `as Type` assertion |
| Untyped library | `// @ts-expect-error <reason>` + open a typing PR upstream |
| Variadic params | Generic `<T>` or discriminated union |
| Test mock | `Partial<T>` or test-runner-specific mock helpers |

### Legitimate exceptions (rare)

- `Record<string, any>` where any-key any-value JSON is the actual contract — even here, prefer `unknown`.
- `catch (e: any)` in pre-TS-4.4 code; modern codebases should use `unknown`.

### Quick search

```bash
grep -rn ":\s*any\b" <project-source-dir> --include="*.ts" --include="*.tsx" | wc -l
# Target: 0
```

### Project-local note

If your project does NOT use TypeScript (pure JavaScript), delete this rule. If your project allows `any` in specific paths (e.g., test fixtures), edit the `file_path` regex to exclude those paths.

**Warn-only — operation proceeds. Pre-merge review (Q2) may upgrade this to a blocker if the issue scores ≥ 80.**
