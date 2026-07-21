# The hard parts — where a generic answer goes wrong

A strong model already catches the basics (processor order, `logging` → `debug`,
pull-vs-push). These are the things it gets *inconsistently right* — encode them
so the answer is correct every time, not when the model happens to remember.

## 1. OTTL — the transform/filter language people invent syntax for

The `transform` and `filter` processors use **OTTL** (OpenTelemetry Transformation
Language), not jq, not SQL, not `attr = value`. The rules:

- Statements are **function calls**: `set(...)`, `delete_key(...)`, `keep_keys(...)`,
  `replace_pattern(...)`, `limit(...)`, `truncate_all(...)`. You do **not** write
  `attributes["x"] = "y"`.
- A condition uses a trailing `where`: `set(attributes["env"], "prod") where attributes["env"] == nil`.
- `error_mode: ignore` (or `silent`/`propagate`) controls what happens when a
  statement errors on a record — set it deliberately.
- Regexes are Go **RE2**: no lookahead, no lookbehind. `(?=...)` does not compile.

### The live confusion: two statement forms, and you must not mix them

There are two ways to write the same statement, and they use **different path
syntax**. Picking one is fine; mixing them is a parse failure.

**Inferred form** (what the processor docs lead with) — a flat statement list where
every path carries its context prefix, and the processor infers the context:

```yaml
trace_statements:
  - set(span.attributes["deployment.environment"], "prod") where span.attributes["deployment.environment"] == nil
  - set(resource.attributes["deployment.tier"], "backend") where IsMatch(resource.attributes["service.name"], "^api-")
```

**Explicit form** — a `context:` block, inside which paths are written **bare**,
because the context already says what they refer to:

```yaml
trace_statements:
  - context: span
    statements:
      - set(attributes["deployment.environment"], "prod") where attributes["deployment.environment"] == nil
  - context: resource
    statements:
      - set(attributes["deployment.tier"], "backend") where IsMatch(attributes["service.name"], "^api-")
```

Both work. The trap is writing `span.attributes[...]` *inside* a `context: span`
block, or bare `attributes[...]` in a flat list — those don't parse. The explicit
form is not deprecated; the docs simply present inference as the default because it
picks the most efficient context for you.

One thing the form does **not** change: if the condition and the target are both
resource-level (as in the `deployment.tier` example), do it at resource scope. A
resource is shared by every span in the batch, so setting a resource attribute from
span scope applies it to siblings you didn't intend.

`transform` processor, explicit form:

```yaml
processors:
  transform:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          - set(attributes["deployment.environment"], "prod") where attributes["deployment.environment"] == nil
          - delete_key(attributes, "http.request.header.authorization")   # scrub a secret header
          - replace_pattern(attributes["url.path"], "/users/[0-9]+", "/users/{id}")  # reduce cardinality
    metric_statements:
      - context: datapoint
        statements:
          - set(attributes["service"], resource.attributes["service.name"])
```

> Version note: newer Collectors also accept **flat statements** where the context
> is inferred from the path (`statements: [ 'set(span.attributes["x"], "y")' ]`)
> and the explicit `context:` grouping is being phased out. The grouped form above
> still works everywhere today; if you target a very recent build, prefer the flat
> form. Either way, the **functions and `where`** are the part models get wrong.

`filter` processor — drop data with OTTL conditions (note: a matching condition
**drops** the record):

```yaml
processors:
  filter/drop_health:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/healthz"'
        - 'attributes["http.route"] == "/readyz"'
```

## 2. spanmetrics connector — it is wired in TWO pipelines, not one

Deriving RED metrics (rate/errors/duration) from spans uses the `spanmetrics`
**connector**. A connector is an **exporter in the source pipeline** and a
**receiver in the destination pipeline** — list it in both, or you get nothing
(or a "connector used as exporter but never as receiver" error). The classic
mistake is wiring it once.

```yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [5ms, 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2s, 5s]
    dimensions:
      - name: http.method
      - name: http.route
    exemplars:
      enabled: true          # lets Grafana jump metric → exemplar trace

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [spanmetrics, otlp]        # <-- connector AS EXPORTER (plus your real trace backend)
    metrics/spanmetrics:
      receivers: [spanmetrics]              # <-- SAME connector AS RECEIVER
      processors: [batch]
      exporters: [prometheusremotewrite]
```

## 3. resource_to_telemetry_conversion — why your `service.name` label is missing

By default the Prometheus/`prometheusremotewrite` exporter puts resource
attributes only on a separate `target_info` series, **not** on each metric. People
expect `service.name`, `deployment.environment`, etc. as labels on every series and
are baffled when they're absent.

This is a trade-off with two valid answers — pick one deliberately and say which.

**Option A — leave it off (the default), join at query time.** Series stay lean;
`service.name` is reachable through `target_info`:

```promql
sum(rate(calls_total[5m])) * on (job, instance) group_left(service_name) target_info
```

Keep `target_info: enabled: true` so the joinable series exists.

**Option B — turn it on, but scrub first.** The conversion copies *every* resource
attribute onto *every* series, including `k8s.pod.name`, `container.id`, `host.id`
— that multiplies series count by pod count. Only enable it after dropping the
high-cardinality attributes:

```yaml
processors:
  transform/trim_resource_attrs:
    error_mode: ignore
    metric_statements:
      - context: resource
        statements:
          - delete_key(attributes, "k8s.pod.name")
          - delete_key(attributes, "k8s.pod.uid")
          - delete_key(attributes, "container.id")
          - delete_key(attributes, "host.id")

exporters:
  prometheusremotewrite:
    endpoint: ${env:MIMIR_ENDPOINT}
    resource_to_telemetry_conversion:
      enabled: true        # safe only because the transform above ran first
    target_info:
      enabled: true
```

Enabling it without the scrub is the cardinality failure people hit in production.

## 4. tail_sampling at scale needs a load-balancing tier

`tail_sampling` makes its keep/drop decision after seeing a whole trace, so **every
span of a trace must reach the same Collector instance**. Put tail_sampling behind
an ordinary load balancer with >1 replica and you shard spans of one trace across
instances → broken, inconsistent sampling. The correct topology is two tiers:

- **Tier 1 (agents/gateway):** receive OTLP, export with the `loadbalancing`
  exporter keyed by `traceID` → routes all spans of a trace to one tier-2 instance.
- **Tier 2 (samplers):** run `tail_sampling`, then export to the backend.

```yaml
# --- Tier 1 ---
exporters:
  loadbalancing:
    routing_key: traceID
    protocol:
      otlp:
        tls: { insecure: true }
    resolver:
      dns:
        hostname: otelcol-sampler.observability.svc.cluster.local
        port: 4317
# tier-1 traces pipeline exporters: [loadbalancing]

# --- Tier 2 (sampler) ---
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 500 }
      - name: sample-rest
        type: probabilistic
        probabilistic: { sampling_percentage: 10 }
# tier-2 traces pipeline processors: [memory_limiter, tail_sampling, batch]
```

`tail_sampling` goes **before `batch`**, and `decision_wait` must exceed your
expected trace duration or late spans get dropped from the decision.

## 5. Exporter reliability — the part that's silently missing in prod

Default exporters drop data on transient backend failure. For anything real, enable
retry **and** a queue. Retry alone only re-attempts the request in flight; without a
queue there is nowhere to park the backlog that arrives during the outage.

**The queue key is per-exporter.** `otlp`/`otlphttp` use the shared exporterhelper
`sending_queue`, which can be persisted with a `file_storage` extension:

```yaml
exporters:
  otlp:
    endpoint: ${env:TEMPO_ENDPOINT}
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s
    sending_queue:
      enabled: true
      queue_size: 5000
      storage: file_storage/queue   # survives a restart; needs a persistent volume

extensions:
  file_storage/queue:
    directory: /var/lib/otelcol/queue
    create_directory: true          # otherwise startup fails if the path is absent
# and list file_storage/queue in service.extensions
```

`prometheusremotewrite` does **not** accept `sending_queue` — it is rejected at
startup (`'prometheusremotewriteexporter.Config' has invalid keys: sending_queue`).
Its key is `remote_write_queue`, and that queue is **memory-only**: it takes no
`storage:`, so a restart loses the backlog.

That is not the same as "this exporter has no durability". It ships its own
write-ahead log, which is the on-disk path here:

```yaml
exporters:
  prometheusremotewrite:
    endpoint: ${env:MIMIR_ENDPOINT}
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s
    remote_write_queue:
      enabled: true
      queue_size: 10000
      num_consumers: 5
    wal:
      directory: /var/lib/otelcol/prw-wal   # persistent volume, not emptyDir
      buffer_size: 300
      truncate_frequency: 60s
```

Honest ceiling: whatever sits in the in-memory queue but is not yet WAL-committed,
plus the `batch` window upstream, is still lost on an ungraceful kill. If the
requirement is a hard "no loss", move the path to `otlphttp` +
`sending_queue.storage` against an OTLP-capable backend instead.

## 6. memory_limiter sizing
Set both `limit_mib` and `spike_limit_mib` (~20% of limit), and give the container
headroom: the hard limit should sit *below* the container memory limit, and pair it
with `GOMEMLIMIT`. Limiter first, always.
