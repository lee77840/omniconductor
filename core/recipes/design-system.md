---
recipe_id: design-system
recipe_name: "Design-token discipline"
applies_when: "Project has a design-token system (color/spacing/typography tokens)"
severity: STRONG (when installed)
ships_hookify:
  - warn-raw-hex-instead-of-token
---

# Recipe — Design-Token Discipline

> Opt-in recipe. Install on projects that maintain a design-token system (color / spacing / typography tokens). Projects with no token system skip this recipe.

## 1. Tokens, not literals

Component styling references design tokens (color / spacing / typography), never raw hex colors or magic pixel values. A raw literal defeats theming: it cannot follow a dark-mode switch, a brand re-skin, or a density change, and it silently drifts from the rest of the system. Every visual value a component renders should resolve through a named token, so a single token edit propagates everywhere consistently.

## 2. Out of scope for this recipe

Which UI library, which icon pack, and which specific token names a project uses are **project-local** decisions, not framework policy (ADR-018). CONDUCTOR does not ship a banlist of libraries or a fixed set of token names — those belong in the adopter project. This recipe enforces only the *principle*: a token over a literal. The adopter supplies the concrete token vocabulary; the recipe supplies the discipline.

## 3. Shipped hookify

This recipe ships one recipe-scoped hookify rule, emitted only when `design-system` is selected via `--recipes`:

| Template | Event | Action | Trigger |
|---|---|---|---|
| `warn-raw-hex-instead-of-token` | file | warn | An inline raw hex color (`#rrggbb`) added to a `.tsx` / `.jsx` / `.css` / `.scss` file |

The rule warns (it never blocks): an intentional one-off outside the token system stays possible, but the author is prompted to justify it rather than drift by accident.
