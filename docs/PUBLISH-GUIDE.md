# Conductor — Marketplace Publish Guide

How to package and publish the Phase 2 VSCode extension to the **VSCode Marketplace** (Microsoft) and the **Open VSX Registry** (Eclipse Foundation, used by Cursor + open-source forks).

This is a **manual procedure** — the extension code lives in `phase-2/vscode-extension/`, but registry credentials are personal/organizational secrets and never live in the repo.

---

## 0. Prerequisites (one-time)

```bash
cd phase-2/vscode-extension
npm install
npm install -g @vscode/vsce ovsx   # or use npx
```

Verify the icon exists at `images/icon.png` (replace the placeholder before first publish — see CHANGELOG).

## 1. Local build + package

```bash
cd phase-2/vscode-extension
npm run compile
npx vsce package
```

Output: `conductor-0.3.0.vsix` in the extension dir. Expected size: < 200 KB (no bundled rules — the extension only ships compiled JS).

Smoke-test the .vsix locally before publishing:

```bash
code --install-extension conductor-0.3.0.vsix
# In VSCode: Cmd/Ctrl+Shift+P → "Conductor: Install" should appear.
code --uninstall-extension lfamily-labs.conductor
```

---

## 2. VSCode Marketplace publish (Microsoft)

### 2.1 Publisher account (one-time)

1. Sign in at https://dev.azure.com with a Microsoft account.
2. Create an organization (any name, used internally only).
3. Open https://marketplace.visualstudio.com/manage and create a publisher with **Publisher ID `lfamily-labs`** (matches `package.json` `"publisher"`).
4. Sign the Microsoft Marketplace Publisher Agreement.

### 2.2 Personal Access Token (PAT)

1. Azure DevOps → User settings → Personal access tokens → New token.
2. **Organization**: All accessible organizations.
3. **Scopes**: custom-defined → **Marketplace → Manage** (everything else off).
4. **Expiration**: 1 year.
5. Copy the token — it is shown once.

Store the PAT in 1Password (or your secrets vault of choice) under `Conductor / VSCode Marketplace PAT` — same convention you use for other long-lived publisher credentials.

### 2.3 Login + publish

```bash
cd phase-2/vscode-extension
npx vsce login lfamily-labs
# Paste the PAT when prompted.

npx vsce publish
# Or publish a specific .vsix:
# npx vsce publish --packagePath conductor-0.3.0.vsix
```

Verify: https://marketplace.visualstudio.com/items?itemName=lfamily-labs.conductor (5-10 min indexing delay).

---

## 3. Open VSX Registry publish (Cursor / forks)

### 3.1 Publisher account (one-time)

1. Sign in at https://open-vsx.org with GitHub.
2. Create a namespace `lfamily-labs` (must match `package.json` `"publisher"`).
3. Sign the [Eclipse Foundation Publisher Agreement](https://open-vsx.org/user-settings/profile) — required before first publish.

### 3.2 Personal Access Token

1. https://open-vsx.org/user-settings/tokens → Generate new token.
2. Description: `Conductor publish`.
3. Copy the token.

Store in 1Password under `Conductor / Open VSX PAT`.

### 3.3 Publish

```bash
cd phase-2/vscode-extension
npx ovsx create-namespace lfamily-labs -p <OPEN_VSX_PAT>   # one-time
npx ovsx publish conductor-0.3.0.vsix -p <OPEN_VSX_PAT>
```

Verify: https://open-vsx.org/extension/lfamily-labs/conductor

---

## 4. Updating to a new version

Per release:

1. Bump `package.json` `version` (semver).
2. Add a `## [x.y.z] — YYYY-MM-DD` block in `CHANGELOG.md`.
3. Build + package:
   ```bash
   npm run compile && npx vsce package
   ```
4. Cross-publish:
   ```bash
   npx vsce publish
   npx ovsx publish conductor-<version>.vsix -p <OPEN_VSX_PAT>
   ```
5. Tag in git: `git tag vscode-ext-v<version> && git push --tags`.

Both marketplaces accept the same `.vsix` artifact — no separate build per registry.

---

## 5. Common publish failures

| Symptom | Fix |
|---|---|
| `vsce` rejects with "missing repository" | Ensure `package.json` `repository.url` is set + reachable. |
| `ovsx` rejects with "namespace not found" | Run `ovsx create-namespace` once. |
| Marketplace shows extension but icon is blank | Replace `images/icon.png` placeholder with a 128x128 square PNG. |
| PAT expired mid-publish | Regenerate (Section 2.2 / 3.2), re-login. |
| `Cannot publish — manifest contains 'name' that doesn't match publisher` | `package.json` `publisher` must equal the registered publisher ID exactly. |

---

## 6. Roadmap (post-marketplace)

- **Auto-update telemetry** — opt-in install count via `vsce` analytics dashboard.
- **CI publishing** — GitHub Action that publishes on tag push (deferred until Phase 3, gated on the adopter project's CI-quota recovery).
- **JetBrains plugin** — separate registry, separate dispatch (ADR-025 "out of scope").

References: ADR-023 (marketplace strategy), ADR-025 (extension architecture).
