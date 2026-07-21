# Scenario: does the description get the skill loaded?

The `description` decides whether an agent loads this skill at all. It is tested
separately from the body, because the failure mode is different: the skill is
never opened.

## Method

Give a fresh agent a menu of ~6 skill descriptions — this one plus plausible
decoys (Prometheus server tuning, Grafana dashboards, k8s debugging, Helm charts,
Loki/LogQL) — and a user request. Ask which skill(s) it would load and why, based
on descriptions alone. Do not let it read any skill body.

Three request types, all three must pass:

| Request | Expected |
|---|---|
| **Direct** — "My otel collector config isn't sending metrics to Prometheus remote write." | this skill selected |
| **Symptom-only** — "Our telemetry pipeline pod starts up fine with no errors, but nothing ever arrives at the backend. And the few metrics that do land are missing the service name label so I can't group by service." | this skill selected — note the request contains **none** of the trigger keywords |
| **Control** — "We have 500 scrape targets and Prometheus is using too much disk. I need to tune retention and the scrape intervals." | this skill **not** selected |

The control matters as much as the hits. A description broad enough to win every
request is a description that will be loaded when it is useless.

## Why the description is trigger-only

It deliberately does not summarise what the skill does. A description that
summarises the workflow gives agents a shortcut they will take instead of reading
the body — the body becomes documentation nobody opens.

Adding the symptom clause ("starts but no data arrives, a component is rejected at
startup, or metrics lack expected labels") was a discovery *gain*, not just rule
compliance: it is what wins the symptom-only request above, which the
keyword list alone would have missed.
