# REMAINING TASKS — `<your-project>`

> **What this is**: open scope dashboard. Things that need to ship before launch / before next milestone.
> Updated when scope changes. NOT a daily task tracker (that's TASKS.md).

> **Status (P0 placeholder)**: replace contents on first install. P1 fills with a more developed example.

---

## Launch readiness

| Area | Status | Owner | Blocker |
|---|---|---|---|
| Auth flow | ⚠️ partial | (you) | (e.g., social login pending) |
| Billing | ⏳ planned | (you) | (e.g., payment-provider live activation) |
| Email infra | ✅ done | — | — |
| Mobile parity | ⚠️ partial | (you) | (e.g., iOS push notifications pending) |
| (add rows per area) | | | |

---

## Cross-cutting tasks

- [ ] (e.g., "i18n sync — propagate pricing copy across 8 locales")
- [ ] (e.g., "audit all `console.error` → migrate to `logError()`")
- [ ] (e.g., "verify CSP headers on production")

---

## Deferred (post-launch)

- [ ] (e.g., "bank-aggregator integration")
- [ ] (e.g., "Spring Boot microservices migration")
- [ ] (e.g., "GUI installer")

---

## How to use this file

- One row per launch-blocking area.
- Update status when it changes (⏳ planned / ⚠️ partial / ✅ done / ❌ blocked).
- When all areas are ✅, you're launch-ready.
- When a blocker resolves, mention it in `docs/CURRENT_WORK.md` session log.
