# OpenTelemetry Tail Sampling — runnable example

A hands-on companion to `OpenTelemetry-Sampling-Guide.md`. That guide covers
the *strategy* (head vs. tail, why the SDK is head-only, the trade-offs); this
one is the *runbook* for a concrete, ready-to-run setup: an OpenTelemetry
Collector doing tail sampling in front of Jaeger and/or VictoriaTraces, wired
to the `otlp-demo` app.

The SDK has no tail sampling by design — it is a head-only sampler, like every
other OpenTelemetry SDK (see the [Custom Sampler guide](OpenTelemetry-Custom-Sampler-Guide.md)).
Tail sampling belongs in the Collector, which can buffer a whole trace before
deciding. Exporters never sample — their only job is to serialize and ship
spans — so the choice of Jaeger vs. VictoriaTraces is irrelevant to sampling.

## Where the files live

The config is kept **outside** the `hs-opentelemetry/` subtree, in the
top-level `jitsurei/` directory, so that `git subtree pull` of upstream never
conflicts with it:

```
jitsurei/
└── tail-sampling/
    └── collector-config.yaml      # the config this doc walks through
```

Anything under `hs-opentelemetry/` is upstream-owned and is overwritten on the
next sync; `jitsurei/` is ours. See `jitsurei/README.md`.

## The pipeline

```
hs-opentelemetry app
      │  OTLP, always_on (export everything)
      ▼
OTel Collector (contrib)
   receivers: otlp
   processors: [tail_sampling, batch]
      │  only the kept traces
      ▼
Jaeger  and/or  VictoriaTraces
```

Two non-negotiables make this work:

1. **The app must not head-sample.** Tail sampling can only weigh spans the
   Collector actually receives. Keep the SDK at `always_on` /
   `parentbased_always_on` so complete traces arrive. The `otlp-demo`'s
   `otel-config.yaml` sets no sampler, so it already defaults to
   `parentbased_always_on` — correct as-is.
2. **The Collector must be the *contrib* build.** The `tail_sampling`
   processor ships only in `otel/opentelemetry-collector-contrib`, not the
   core collector. The demo's `docker-compose.yml` already uses the contrib
   image.

## The sampling policy

The three policies in `collector-config.yaml` are **OR-combined** — a trace is
kept if *any* of them votes to sample it:

| Policy | Type | Keeps |
|---|---|---|
| `keep-errors` | `status_code` = `ERROR` | every trace with an error span (100%) |
| `keep-slow` | `latency` ≥ 500ms | every slow trace end-to-end |
| `baseline-5pct` | `probabilistic` 5% | a random 5% of everything else |

So you retain *all* the interesting traces (errors + slow) plus a thin
statistical floor of healthy ones for baselines. Tune the threshold and
percentage to taste.

The other knob that matters is **`decision_wait`** (10s in the config): how
long the Collector buffers a trace before deciding. It must exceed your slowest
end-to-end trace duration, or spans that arrive after the decision are dropped
and you get truncated traces. The cost of a larger window is export latency and
memory (`num_traces` × spans-per-trace × span size held in RAM).

## Standing it up against the otlp-demo

The demo lives at `hs-opentelemetry/examples/otlp-demo/`. Point its Collector
at the `jitsurei` config and add the backend(s) you want.

### 1. Mount the tail-sampling config

In `hs-opentelemetry/examples/otlp-demo/docker-compose.yml`, change the
collector's volume mount to the out-of-subtree config (path is relative to the
compose file):

```yaml
  collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otel/config.yaml"]
    volumes:
      - ../../../jitsurei/tail-sampling/collector-config.yaml:/etc/otel/config.yaml:ro
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
```

### 2. Add the backend services

Add alongside `collector`. Keep whichever backend you want and delete the
other (and remove its exporter from the pipeline in `collector-config.yaml`):

```yaml
  jaeger:
    image: jaegertracing/all-in-one:latest
    environment:
      - COLLECTOR_OTLP_ENABLED=true     # exposes OTLP on 4317/4318
    ports:
      - "16686:16686"                   # Jaeger UI

  victoria-traces:
    image: victoriametrics/victoria-traces:latest   # verify image/tag — VictoriaTraces is new
    ports:
      - "10428:10428"
```

- **Jaeger** is OTLP-native (v1.35+ with `COLLECTOR_OTLP_ENABLED`, or v2 by
  default). The config's `otlp/jaeger` exporter points at `jaeger:4317`.
- **VictoriaTraces** ingests via OTLP HTTP at a custom path. The config's
  `otlphttp/victoria` exporter uses
  `http://victoria-traces:10428/insert/opentelemetry/v1/traces` — **verify the
  host/port/path against your VictoriaTraces version's docs**; it is a young
  project and the ingestion path may differ.

### 3. Run and verify

```bash
cd hs-opentelemetry/examples/otlp-demo
docker compose up
```

Then exercise the app so it produces a mix of healthy, errored, and slow
traces. You should see:

- **Errored and slow traces** appear in the backend essentially always.
- **Healthy traces** appear ~5% of the time.
- The Collector's `debug` exporter (left in the traces pipeline) logs what
  survives sampling — handy while tuning the policies. Drop it once you trust
  the config.

Jaeger's UI is at <http://localhost:16686>; filter by error or by duration to
confirm the interesting traces are being retained.

## Scaling caveat

A single Collector is fine for the demo and most single-node deployments. Tail
sampling breaks across multiple Collector replicas, because each replica would
see only part of a trace. The standard fix is a first tier of Collectors
running a `loadbalancing` exporter keyed by trace ID, feeding a second tier
that runs `tail_sampling`. This is noted at the bottom of
`collector-config.yaml` so it is not a surprise later.

## Related guides

- `OpenTelemetry-Sampling-Guide.md` — head vs. tail sampling strategy, the
  built-in samplers, and the in-process filtering-processor approximation.
- `OpenTelemetry-Custom-Sampler-Guide.md` — writing a head `Sampler`.
- `OpenTelemetry-Exporters-Guide.md` — the OTLP exporter the app uses to reach
  the Collector.
- `OpenTelemetry-Propagators-Guide.md` — how the `sampled` flag and trace
  context travel between services.
