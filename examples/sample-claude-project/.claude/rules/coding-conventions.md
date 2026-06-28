---
paths:
  - "**"
---

---
recipe_id: coding-conventions
recipe_name: "TypeScript-first coding conventions"
applies_when: "TypeScript / TSX project that wants explicit naming + error-handling + type-safety conventions"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
---

# Recipe — Coding Conventions

> Opt-in recipe. Install on TypeScript / TSX projects that want explicit naming, error-handling, and type-safety conventions. Adopters in other languages (Go, Rust, Python) skip this recipe and write their own.

## 1. Naming

| Kind | Convention | Example |
|---|---|---|
| Components / Types / Interfaces | PascalCase | `AccountCard.tsx`, `interface Account` |
| Files (non-component) | camelCase | `accounts.ts` |
| Functions / Variables | camelCase | `getAccounts()`, `accountId` |
| Constants | UPPER_SNAKE_CASE | `MAX_POINTS` |
| Folders | kebab-case | `lib/db-client/` |
| Booleans | `is` / `has` prefix | `isLoading`, `hasError` |
| Event handlers | `on` prefix | `onClick`, `onSubmit` |

## 2. TypeScript

- Always `.ts` / `.tsx`. Never `.js` / `.jsx` in source.
- Explicit types on EVERY function parameter and return value. No "rely on inference for top-level signatures".
- The `any` type is FORBIDDEN. When the type is genuinely unknown, use `unknown` and narrow.
- Shared types live in the project's shared package (`packages/shared` or equivalent) when consumed by multiple apps; otherwise in a local `types/` directory.
- `as` casts are last-resort. Prefer type guards.

## 3. Error handling — Result pattern

Service functions return a Result tuple, not throw exceptions:

```typescript
type Result<T> = { data: T; error: null } | { data: null; error: string };

async function getAccounts(userId: string): Promise<Result<Account[]>> {
  const { data, error } = await db.from('accounts').select().eq('user_id', userId);
  if (error) {
    logError(error, { context: 'getAccounts', userId });
    return { data: null, error: error.message };
  }
  return { data, error: null };
}
```

### 3.1 Why Result-pattern (not exceptions)

- Forces the caller to handle the error case at the call site.
- Type system surfaces the error path in the function signature.
- Avoids "try/catch the world" patterns that swallow errors.
- Stack traces are not the primary error-comm channel; the structured error string is.

### 3.2 The structured logger rule

Always use the project's `logError()` (or equivalent structured-logging utility) — never raw `console.error`. Why:

- `logError()` includes context (user id, request id, feature flag, environment).
- `logError()` ships to the project's observability platform (your error-aggregation service of choice).
- Raw `console.error` gets lost in serverless function logs and produces no alert.

## 4. Error UX patterns

| Surface | Pattern |
|---|---|
| Page-level fatal error (load failed) | Project's error-banner component (e.g., `ErrorBanner`) |
| Action feedback (save success, validation error) | Project's toast utility (e.g., `toast.success()` / `toast.error()`) |
| Form field error | Inline error message under field |
| API response | Result-pattern JSON: `{ data, error }` |

User-facing error messages MUST be translated (i18n key, not raw error string from the service). The raw error goes to the logger; the translated message goes to the UI.

## 5. Forbidden

- Hardcoded secrets / API keys / tokens — load from environment at runtime.
- Service-role / admin keys in client code — server-side only.
- Untyped escape hatches (`any`, `as unknown as Foo`).
- UI libraries beyond the project's approved set (the rule index lists them — typically a single primary library).
- Hardcoded user-facing strings on multi-locale projects (use translation keys — see `recipes/i18n.md`).
- Duplicated business logic between apps in a monorepo (it goes in shared — see `recipes/monorepo.md`).

## 6. Folder conventions (TypeScript app)

```
apps/<app>/
├── app/                ← Next.js app router (or equivalent framework structure)
├── components/         ← Reusable UI components
│   ├── common/         ← Cross-feature primitives (ErrorBanner, etc.)
│   └── <feature>/      ← Feature-scoped components
├── lib/
│   ├── i18n/           ← Translation hook + per-app local copy
│   └── utils/          ← Pure utilities (errorLogger, formatters, etc.)
├── services/           ← Service-layer functions (Result pattern)
└── types/              ← Local types (not consumed by other apps)
```

The recipe is the rule; the project's framework dictates the actual structure.

## 7. Test discipline

| Test type | Location | When required |
|---|---|---|
| Unit | `<file>.test.ts` co-located | New service function, new utility |
| E2E functional | `apps/<app>/e2e/functional/` | New page / flow / API endpoint |
| Visual smoke | `apps/<app>/e2e/visual/` | New page / screen |
| Snapshot | `<feature>/__tests__/` | New email template, new render-only artifact |

The full test sync rule is in `quality-gates.md` Q3. This recipe enumerates the test types specifically for the TypeScript stack.

## 8. Cross-tool enforcement

| Mechanism | Where |
|---|---|
| TypeScript strict mode | `tsconfig.json` `"strict": true` |
| `any` ban | ESLint rule (`@typescript-eslint/no-explicit-any`) |
| Naming conventions | ESLint rule (`@typescript-eslint/naming-convention`) |
| Result pattern | Reviewer checklist + `coding-conventions` rule loaded into tool context |
| Hardcoded string ban | ESLint custom rule (when present) + reviewer checklist |
| `console.error` ban | ESLint rule + reviewer checklist |
