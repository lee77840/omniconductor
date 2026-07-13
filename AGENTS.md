# CONDUCTOR repository instructions

This repository is maintained with the same rules in every supported coding tool.
Read `CURRENT_WORK.md`, `SESSION_HANDOFF.md`, and the relevant files under `docs/`
before changing implementation.

- Keep portable rules in `core/`; compile tool-native behavior in one of the six
  `adapters/<tool>/transform.sh` implementations.
- Preserve the immutable difficulty definitions in
  `core/universal-rules/meta-discipline.md`. Use the project-saved Tier mapping;
  never substitute Claude model family names as universal difficulty labels.
- The eight baseline roles are planner, reviewer, code-reviewer, builder, helper,
  designer, scribe, and utility. Reflector is opt-in.
- Treat Claude Code, Cursor, GitHub Copilot, Gemini CLI, Codex, and Windsurf as
  first-class adapters. State enforcement per verified native contract; do not
  describe a feature as provider-exclusive when another adapter emits it.
- Do not modify the sibling reference application. Sanitize any read-only source
  material before it enters this repository.
- Record architectural changes in `docs/DESIGN-DECISIONS.md`, update every stale
  count or claim in the same change, and keep public/private publication safety.
- Before declaring completion, run the relevant install-mode, model-routing,
  path-safety, validator, doctor, metadata, generated-doc, and package checks.

Provider-specific bootstrap files may add native mechanics, but they may not
override this shared contract or its Tier definitions.
