---
name: block-server-secret-in-client
enabled: true
event: file
action: block
conditions:
  - field: file_path
    operator: regex_match
    pattern: (src/(components|hooks|pages|ui)|public)/.*\.(ts|tsx|js|jsx)$
  - field: new_text
    operator: regex_match
    pattern: (SERVICE_ROLE_KEY|SERVICE_ROLE|_SECRET_KEY|_PRIVATE_KEY|ADMIN_API_KEY|SECRET_ACCESS_KEY)
---

🚨 **CRITICAL — server-only secret in client-bundled code (blocked)**

A server-only secret pattern was added to a file that ships in the client bundle. **Blocked.**

### Why this is critical

- Client bundles are downloadable by every user of the app. A server secret placed in client code is extractable from the shipped bundle.
- A single exposure means the key must be rotated immediately (incident response), not just edited out.
- Build tooling will happily inline the value — there is no compile-time guard unless one is added (this rule is that guard).

### The correct split

| Surface | Key type |
|---|---|
| Client (browser / mobile) | Public / anon key only — scoped, safe to ship |
| Server (API route / server action / serverless function / build script) | Secret / privileged key — never imported into client paths |

### If this matched a genuine server-only file

The path matched `(src/(components|hooks|pages|ui)|public)/.*\.(ts|tsx|js|jsx)$` but is actually server-only — move it under a server-only directory, or narrow `CONDUCTOR_CLIENT_GLOB` for this project. Then retry.

**block — operation halted. Relocate the secret to a server-only path and retry.**
