# Tests

This skill is developed test-first: a change is only made after watching agents
fail without it, and only kept after watching agents comply with it.

**The rule:** if you did not watch an agent fail without the guidance, you do not
know whether the guidance teaches the right thing. That applies to edits, not just
new sections.

## What is here

| File | Purpose |
|---|---|
| `validate-examples.sh` | Regression check for `examples/` against a current Collector build. Run it after any example edit and after Collector releases. |
| `scenarios/` | The prompts used to test the skill itself, with the outcome each one is checking for. |

## Running the example regression

```bash
tests/validate-examples.sh                                     # default image
tests/validate-examples.sh otel/opentelemetry-collector-contrib:0.160.0
```

Note the two passing examples use `${env:...}` endpoints. Validation resolves env
expansion first, so a bare `validate --config=examples/fixed-config.yaml` reports
`requires a non-empty "endpoint"` — that is env expansion, not a broken config.
The script supplies placeholder values.

## Running a skill scenario

Each file in `scenarios/` is a prompt plus the behaviour it checks. Run it with a
fresh agent that has no other context.

- **Baseline (RED):** run the prompt *without* pointing the agent at `SKILL.md`.
  Record what it does wrong, verbatim.
- **Verify (GREEN):** run the same prompt with the agent told to read `SKILL.md`
  first. The recorded failure should be gone.
- **Repeat 2–3 times per arm.** A single run lies. Convergence across runs is the
  signal that the guidance is binding; three different shapes means it is not.

Always keep a no-guidance control. If the baseline does *not* exhibit the failure,
there is nothing to fix — do not write the guidance.

## What the last round found

Worth knowing before adding to this skill:

- The basics (connector dual-wiring, processor order, core-vs-contrib, cumulative
  temporality) were already correct in **every** baseline run. Documenting what the
  model already knows adds length, not value.
- The value is where capable agents *diverge*. Every change kept in the last two
  rounds came from a divergence, not from a gap someone imagined while reading.
- Two separate regressions had the same shape: a **partially-true generalisation**
  made agents abandon a safety mechanism outside its stated boundary
  ("retry + `sending_queue`" → dropped queueing entirely when the key was rejected;
  "PRW uses `remote_write_queue`" → concluded no on-disk durability existed at all).
  When writing a rule, state its boundary too.
