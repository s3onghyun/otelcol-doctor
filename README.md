# otelcol-doctor

**A Claude Code / Codex / Cursor skill that writes, fixes, and validates OpenTelemetry Collector configs — and gets the sharp edges right.**

The OpenTelemetry Collector is five concepts and a hundred footguns: processor
order that silently matters, components that only exist in the *contrib* build,
pull-vs-push metric exporters, pipelines that validate fine and do absolutely
nothing because nobody wired them. `otelcol-doctor` teaches your AI agent those
edges so the YAML it hands you actually starts and actually delivers data.

> Plain English in → a correct, commented, **validated** `otelcol` config out.
> Or paste a broken config → a diagnosis (*what's wrong → why → the fix*) and the repaired version.

---

## Why this exists

Every LLM will happily generate an OpenTelemetry Collector config. Most of them
are subtly wrong in ways that cost you an afternoon:

- `batch` placed before `memory_limiter` (so the limiter can't shed load)
- a `prometheus` exporter when you meant `prometheusremotewrite` (pull vs push)
- the removed `logging` exporter, or the deprecated `loki` exporter
- a `prometheus` receiver on the **core** image (crash — it's contrib-only)
- a receiver defined but never referenced in a pipeline (valid YAML, zero data)

This skill encodes those exact failure modes as a checklist the agent runs every
time, then validates the result with `otelcol validate` before declaring done.

## Demo

**In:** *"Collector that takes OTLP from my apps, scrapes Prometheus targets, sends traces to Tempo and metrics to Mimir."*

**Out:** a config with `memory_limiter` first, `batch` last, `otlp` → Tempo,
`prometheusremotewrite` → Mimir, `health_check` wired into `service.extensions`,
env-var endpoints, and a note that it needs the **contrib** image — then:

```
$ scripts/validate.sh config.yaml
→ otelcol-contrib validate
# (exit 0)
```

See [`examples/broken-config.yaml`](examples/broken-config.yaml) → [`examples/fixed-config.yaml`](examples/fixed-config.yaml)
for a five-bug repair walked through line by line.

## Install

It's a single skill file. Drop it where your agent looks for skills:

**Claude Code**
```bash
git clone https://github.com/s3onghyun/otelcol-doctor
mkdir -p ~/.claude/skills/otel-collector-config
cp otelcol-doctor/SKILL.md ~/.claude/skills/otel-collector-config/
cp -r otelcol-doctor/references otelcol-doctor/examples otelcol-doctor/scripts \
      ~/.claude/skills/otel-collector-config/
```

**Codex / Cursor / other agents:** point your skill/rules loader at `SKILL.md`
(it's plain Markdown with standard skill frontmatter).

Then just ask: *"write me an otel collector config that…"* or *"why is no data
reaching my backend?"* and paste the config.

## What's in here

| File | Purpose |
|------|---------|
| `SKILL.md` | The skill: mental model, authoring workflow, and the fix-it checklist. |
| `references/components.md` | Curated catalog of the receivers/processors/exporters/connectors that actually come up, each with its gotcha and the **core vs contrib** split. |
| `examples/` | A broken config and its diagnosed, validated repair. |
| `scripts/validate.sh` | Wraps `otelcol validate` (auto-detects contrib, falls back to Docker). |

## Scope

Focused on the **Collector config** on purpose — not instrumentation SDKs, not
dashboards. Covers traces/metrics/logs pipelines, OTLP/Prometheus/Loki/Tempo/Mimir
export, and the core-vs-contrib distinction. Vendor-neutral.

## Contributing

Found an edge it gets wrong, or a footgun worth encoding? Open an issue or PR
with a before/after config — concrete failure modes are exactly what makes this
useful.

## License

[Apache-2.0](LICENSE)
