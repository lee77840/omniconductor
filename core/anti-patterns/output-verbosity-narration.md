---
anti_pattern_id: output-verbosity-narration
name: "Verbose output / narration — the model over-explains every turn"
type: anti-pattern
severity: MEDIUM
hit_rate_impact: "output-cost, not cache-hit: output tokens priced ~5× input"
detection_method:
  - measure-tokens (output tokens / turn vs KPI baseline)
  - eyeball: preamble + restating the ask + re-printed file bodies
applies_to: ["all-tools"]
linked_rules:
  - meta-discipline (5.9 output brevity)
---

# Anti-Pattern 08 — Verbose output / narration

## 1. What it is

The model spends output tokens on prose that carries no information the user needs: preamble ("Great question! Let me take a look…"), restating the request back, narrating each step before doing it, re-printing whole file bodies after an edit, and a long recap at the end. The *work* may be correct and efficient; the *response describing it* is 3–5× longer than the task warrants.

```
# WRONG — 900-token answer to a one-line question
"That's a great question! Let me think through this carefully. First, I want to
make sure I understand what you're asking. You'd like me to rename the variable
`x` to `count`. Let me explain my approach before I begin. I'll start by locating
every usage… [200 more tokens] … Here is the full updated file: [entire 180-line
file re-printed] … To summarize what I did above, I renamed the variable…"
```

Unlike Anti-Pattern 06 (tool-call spam), which is about too many *tool calls*, this is about too much *generated prose* — it can spike even on a turn with zero tool calls.

## 2. Why it costs

- **Output is a controllable expense.** Pricing ratios vary by provider, but a turn that could answer in 150 output tokens and spends 900 still uses 6× the output, latency, and context.
- **It compounds into input next turn.** Every verbose response becomes conversation history that is re-read (cache-read, but still billed) on every subsequent turn until compaction. Bloated output today is bloated input for the rest of the session.
- **Re-printed file bodies are the worst offender** — a single re-printed 180-line file after an edit can be 2K+ output tokens that the Edit tool already captured for free.

Conductor's P1.5 baseline targets output tokens / turn ≤ 800; investigate above ~1200.

## 3. Detection

**Quantitative**:
```bash
bash tools/measure-tokens.sh --latest | grep -E 'output tokens'
```
- Output tokens / turn > 1200 sustained → red flag (KPI healthy ≤ 800).
- High output cost on turns with 0–1 tool calls → prose bloat, not tool bloat (distinguishes from Anti-Pattern 06).

**Eyeball signals**: responses that open with preamble, restate the user's request, re-print a file the model just edited, or close with a recap of what was said one screen up.

## 4. Fix / Alternative

**Per `meta-discipline.md` §5.9 (output brevity)**:

- **Answer first, no preamble/postamble.** Lead with the result; cut "Great question", "Let me…", and end-of-turn recaps.
- **Don't restate the ask.** The user knows what they asked.
- **Reference edits, don't reprint them.** After an Edit, say *what* changed and *where* (`file:line`) — the diff already exists; the file body does not need to re-enter the output stream.
- **Right-size the format.** One line for a one-line question; reserve tables/numbered steps for genuinely multi-part work.
- **Cap bounded artifacts** with `max_tokens` (Claude adapter) when the ceiling is known.

**Fidelity guard** (per §5.9): brevity trims prose, never substance. Keep every warning, caveat, failing-test result, or action the user must take. When forced to choose, completeness beats brevity.

## 5. Severity rating

**MEDIUM** — rarely session-breaking on its own, but a steady tax on every turn and the easiest anti-pattern to fix (it costs nothing to stop over-explaining). Worst when combined with re-printed file bodies on edit-heavy sessions.

| Response style | Output tokens / turn | Verdict |
|---|---|---|
| Answer-first, edits by reference | 100–400 | optimal |
| Some narration, occasional recap | 500–800 | acceptable |
| Preamble + restate + recap | 900–1400 | trim |
| Re-prints full files after edits | 1500+ | refactor habit |
