# Component catalog (the ones that actually come up)

Distribution legend: **[core]** ships in `otel/opentelemetry-collector`;
**[contrib]** only in `otel/opentelemetry-collector-contrib` (or a custom `ocb` build).

## Receivers (data in)

| Component | Signals | Dist | Gotcha |
|-----------|---------|------|--------|
| `otlp` | traces, metrics, logs | core | Two listeners: `grpc` (4317) and `http` (4318). Bind `0.0.0.0` for cross-container traffic. |
| `jaeger` | traces | core+contrib | **Legacy ingest only** (beta). Receives Jaeger thrift/gRPC spans — use to migrate apps still emitting Jaeger protocol. New setups use `otlp`. (The jaeger *exporter* was removed — send to Jaeger via OTLP.) |
| `prometheus` | metrics | contrib | Embeds a full Prometheus scrape config under `config.scrape_configs`. Metrics-only. |
| `hostmetrics` | metrics | contrib | Host CPU/mem/disk/net. Needs `scrapers:` block; some scrapers need host mounts/privileges. |
| `filelog` | logs | contrib | Tails files. `include`/`exclude` globs + `operators` for parsing. Watch `start_at: beginning` vs `end`. |
| `kafka` | traces, metrics, logs | contrib | Set `protocol_version`. One receiver instance per signal/topic mapping. |
| `k8s_cluster` / `kubeletstats` | metrics, logs | contrib | Need RBAC + service account in-cluster. |

## Processors (middle, ORDER MATTERS)

| Component | Dist | Gotcha |
|-----------|------|--------|
| `memory_limiter` | core | **Put FIRST.** `check_interval` + `limit_mib` (and optional `spike_limit_mib`). Sheds load to prevent OOM. |
| `batch` | core | **Put LAST**, before export. `send_batch_size`, `timeout`. Improves throughput; don't put before `memory_limiter`. |
| `resourcedetection` | contrib | Adds env/cloud resource attributes (`detectors: [env, system, gcp, ec2…]`). Order before `batch`. |
| `transform` | contrib | OTTL statements — powerful, easy to write a no-op. Test with the `debug` exporter. |
| `filter` | contrib | OTTL conditions to drop data. Easy to drop more than intended; verify. |
| `attributes` / `resource` | contrib | Add/update/delete attributes. `resource` = resource-level, `attributes` = signal-level. |
| `tail_sampling` | contrib | Traces only. Before `batch`. Needs complete traces on one instance → use a `loadbalancing` exporter upstream when scaling out. |

## Exporters (data out)

| Component | Signals | Dist | Gotcha |
|-----------|---------|------|--------|
| `otlp` | all | core | OTLP over **gRPC** (4317). `tls.insecure: true` only for local/plaintext. |
| `otlphttp` | all | core | OTLP over **HTTP** (4318). Use for backends that expose an OTLP/HTTP endpoint (incl. Loki `:3100/otlp`). |
| `debug` | all | core | Console output. `verbosity: detailed` for debugging. **Replaces the removed `logging` exporter.** |
| `prometheus` | metrics | contrib | **PULL** — exposes `/metrics` for Prometheus to scrape. Sets an `endpoint` to listen on. |
| `prometheusremotewrite` | metrics | contrib | **PUSH** — remote-writes to Mimir/Thanos/Cortex or Prometheus with the remote-write receiver enabled. |
| `loki` | logs | — | **Removed** from contrib — use `otlphttp` to Loki's native OTLP endpoint (`:3100/otlp`). |
| `kafka` | all | contrib | Mirror of the kafka receiver; set `protocol_version`. |
| `loadbalancing` | traces, logs | contrib | Routes by key (e.g. trace ID) across backend Collectors — required for sharded `tail_sampling`. |

## Connectors (pipeline → pipeline)

| Component | In → Out | Dist | Use |
|-----------|----------|------|-----|
| `spanmetrics` | traces → metrics | contrib | Derive RED metrics (rate/errors/duration) from spans. Output goes to a **metrics** pipeline. |
| `routing` | any → same | contrib | Fan data to different pipelines by attribute/context. |
| `forward` | same → same | core | Merge/split pipelines without transformation. |

## Extensions (not in the data path)

| Component | Dist | Use |
|-----------|------|-----|
| `health_check` | contrib | Liveness/readiness endpoint. Wire into `service.extensions`. |
| `pprof` | contrib | Go profiling endpoint. |
| `zpages` | core | Live debug pages (`/debug/tracez`). |
| `basicauth` / `oauth2client` / `headers_setter` | contrib | Auth for exporters/receivers via `auth:` refs. |

## Deprecated / removed — replace on sight
- `logging` exporter (removed) → **`debug`**
- `loki` exporter (removed from contrib) → **`otlphttp`** to Loki OTLP endpoint
- `jaeger` **exporter** (removed) → **`otlp`/`otlphttp`** (Jaeger ingests OTLP natively). NB: the `jaeger` **receiver** is *not* removed — still [core]+[contrib], beta, for legacy Jaeger-protocol ingest.
- bare `${VAR}` env syntax → **`${env:VAR}`**
- `service.telemetry.metrics.address` (old) → `service.telemetry.metrics.readers` (newer schema)

## Validate
```
otelcol-contrib validate --config=config.yaml
# or, no local binary:
docker run --rm -v "$PWD/config.yaml:/c.yaml" \
  otel/opentelemetry-collector-contrib:latest validate --config=/c.yaml
```
