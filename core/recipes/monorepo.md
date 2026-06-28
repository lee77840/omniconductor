---
recipe_id: monorepo
recipe_name: "Monorepo structure with shared package"
applies_when: "project uses npm workspaces (or equivalent) with shared code between apps"
severity: STRONG (when installed)
linked_rules:
  - workflow
---

# Recipe — Monorepo Structure

> Opt-in recipe. Install when the project uses npm workspaces (or pnpm / yarn workspaces / turborepo) with shared code between multiple deployable apps. Do NOT install on single-app projects.

## 1. The frozen folder structure rule

Once the monorepo's top-level structure is set (apps + packages + root config), DO NOT change it without explicit authorization.

### 1.1 Why "frozen"

Folder restructures invalidate every cached path: TypeScript paths, IDE workspaces, deploy pipelines, test selectors, documentation references. The cost of a restructure is high enough that "let's clean this up" is not a sufficient justification.

The originating project recorded this as an explicit user instruction: "do not change current monorepo folder structure". The rule generalizes.

## 2. Reference structure (originating project)

```
project-root/
├── apps/
│   ├── web/             ← Next.js app (or equivalent)
│   └── mobile/          ← React Native / Expo app (or equivalent)
├── packages/
│   └── shared/          ← Shared business logic, types, constants, i18n source-of-truth
├── docs/                ← All project documentation
├── .claude/ (or .cursor/ / .github/instructions/ / .windsurf/)
├── package.json         ← root with `workspaces` config
└── ...
```

This is the reference, not the mandate. Adopters with different conventions (e.g., turborepo with `packages/web`, `packages/mobile`) follow the same principle: freeze the top-level layout once decided.

## 3. Shared package contract

Code that goes in `packages/shared`:

- Business logic that runs identically on both surfaces.
- Type definitions consumed by both surfaces.
- Constants (rate limits, feature names, error codes).
- i18n source-of-truth (per `recipes/i18n.md`).

Code that does NOT go in `packages/shared`:

- Surface-specific UI components (web: `<web-app>/components/`; mobile: `<mobile-app>/src/components/`).
- Surface-specific hooks that depend on platform APIs.
- Build / deploy configuration.

## 4. Import direction

```
<web-app>/        →  imports from packages/shared  (one-way)
<mobile-app>/     →  imports from packages/shared  (one-way)
packages/shared/  →  imports nothing from apps/    (HARD RULE)
```

Reverse imports (shared importing from apps/) create build-order cycles and defeat the purpose of the shared package.

### 4.1 Web's "imports from shared" caveat

On some build setups, the web app does NOT import from `packages/shared` directly at runtime — instead it consumes a local copy (this is the i18n recipe's pattern). Whether direct import or local copy is the right pattern depends on the deploy target's module resolution semantics. The recipe documents the convention; the project's own tooling makes it work.

## 5. Code duplication between apps

Duplicated business logic between the web and mobile surfaces is FORBIDDEN. If two surfaces have the same logic, it belongs in `packages/shared`.

The reviewer role's checklist (`roles/reviewer.md`) includes a "no duplicated business logic" check. The check is performed by reading the diffs for both surfaces and looking for parallel logic.

## 6. Test organization

```
<web-app>/e2e/
├── functional/      ← E2E functional specs
├── visual/          ← Visual smoke specs
└── pages.ts         ← Page catalog for visual smoke

<mobile-app>/__tests__/   ← Mobile-specific
packages/shared/__tests__/  ← Unit tests for shared logic
```

Test execution is per-app (each `package.json` has its own test script). Root `package.json` has aggregate scripts that run all apps.

## 7. Deploy pipeline implications

Each app deploys independently. Changes to `packages/shared` trigger redeploys of every app that imports it. CI configuration MUST handle this — typically by running every app's build when shared changes.

## 8. Cross-tool enforcement

| Mechanism | Where |
|---|---|
| Folder structure freeze | Rule text + reviewer checklist |
| Import direction | TypeScript compiler (with `paths` config) + lint rule (e.g., `import/no-internal-modules`) |
| Duplication check | Reviewer role manual check |
| Build coupling | CI configuration (per-app build matrix) |
