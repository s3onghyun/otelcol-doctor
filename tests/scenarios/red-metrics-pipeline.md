# Scenario: RED metrics from spans, traces to Tempo, metrics to Prometheus

Exercises most of the "hard parts" at once: distribution choice, connector
dual-wiring, processor order, sampling placement, remote-write label strategy,
exporter reliability.

## Prompt

> We run services instrumented with OpenTelemetry. I need the Collector to receive
> OTLP traces from them, generate RED metrics (request rate / error rate / duration)
> from those spans, send the traces to Grafana Tempo, and send the generated metrics
> to Prometheus via remote write. This is going to production, so include the usual
> safety basics.
>
> Produce the complete config YAML. Also state which Collector distribution the user
> must run, and briefly explain your pipeline wiring.

Baseline arm: add "Do NOT read any skill or reference files — answer from your own
knowledge." Verify arm: tell the agent to read `SKILL.md` first.

## What to check

| # | Check | Baseline result (3 runs, no skill) |
|---|---|---|
| 1 | contrib named as required | 3/3 correct — low-value to teach |
| 2 | connector wired in both pipelines | 3/3 correct — low-value to teach |
| 3 | `memory_limiter` first, `batch` last | 3/3 correct — low-value to teach |
| 4 | cumulative temporality for remote write | 3/3 correct — low-value to teach |
| 5 | **sampling placed downstream of spanmetrics** | **2/3 forked; 1/3 omitted sampling entirely** |
| 6 | **`resource_to_telemetry_conversion` decision justified** | **split 2:1, with no shared rule** |
| 7 | **every referenced component declared** | **1/3 shipped an undeclared `forward` connector** |

Checks 5–7 are the ones the skill exists for. 1–4 are already reliable without it.

## Failure text to watch for

- A config whose explanation ends with "one thing to fix before you deploy" —
  that is check 7 failing.
- `tail_sampling` in the same pipeline that feeds the `spanmetrics` connector —
  check 5 failing. It looks healthy and understates request rate by the sampling
  ratio.
