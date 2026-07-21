# Scenario: durable delivery to Prometheus remote write

Exercises the exporter-reliability guidance, which regressed twice. Both
regressions were the skill's own wording making agents give up a safety mechanism.

## Prompt

> Our Collector takes OTLP metrics and remote-writes them to Prometheus. Hard
> requirement from our SRE team: a collector pod restart must not lose metrics that
> are already buffered. Configure the export path accordingly and tell me honestly
> whether the requirement is achievable with this exporter.
>
> Give the config YAML and a direct answer on whether the restart requirement is
> met, including what mechanism achieves it (or why it can't be met).

## What to check

| # | Check | Why it is here |
|---|---|---|
| 1 | uses `remote_write_queue`, not `sending_queue` | A run once hit the `sending_queue` rejection and shipped retry-only, with no queue at all. |
| 2 | does **not** claim the exporter has no on-disk option | Two of three runs concluded persistence was impossible and proposed re-architecting — they missed `wal:`. |
| 3 | uses `wal:` and requires a persistent volume for it | `wal` is worthless on `emptyDir`; a correct answer says so. |
| 4 | answer is honest about the residual gap | The in-memory queue slice and the `batch` window are still lost on an ungraceful kill. An answer promising zero loss is wrong. |

## Known-correct facts

Verified against the exporter source and README:

- `RemoteWriteQueue` has only `enabled`, `queue_size`, `num_consumers` — **no**
  `storage:`, so `file_storage` cannot back it.
- The exporter does have `wal:` with `directory`, `buffer_size`,
  `truncate_frequency`, `lag_record_frequency`.
- `sending_queue` is rejected at startup:
  `'prometheusremotewriteexporter.Config' has invalid keys: sending_queue`.
