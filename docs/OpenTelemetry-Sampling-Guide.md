# OpenTelemetry Sampling Guide

This guide covers sampling strategy for `hs-opentelemetry` — what the SDK actually supports, how to configure the built-in samplers, and how to achieve tail-sampling semantics given that the Haskell SDK (like most OpenTelemetry SDKs) is a head-only sampler.

For the mechanics of writing your own `Sampler`, see `OpenTelemetry-Custom-Sampler-Guide.md`. This guide focuses on strategy and on tail sampling specifically.

## Head Sampling vs. Tail Sampling

OpenTelemetry distinguishes two places a sampling decision can be made:

- **Head sampling** happens at span *start*. The decision is made before any work has been done, and propagates across services via the `sampled` flag in the W3C `traceparent` header. This is cheap — dropped spans cost almost nothing — but the decision is uninformed: you do not yet know whether the request will error, will be slow, or will turn out to be interesting.
- **Tail sampling** happens after a trace has completed (or after enough of it has completed to decide). It buffers spans and evaluates the whole trace against a policy — "keep all traces with an error", "keep 1% of successful traces", "keep anything slower than 2s". This gives much higher-value retained traces, but it requires buffering every span in memory somewhere until the decision is made.

The `hs-opentelemetry` SDK implements head sampling only. Tail sampling in this stack is done downstream — almost always in an OpenTelemetry Collector sitting between your app and your backend. The rest of this guide walks through both halves.

## Head Sampling in hs-opentelemetry

### Where the Decision Happens

Head sampling is invoked inside `createSpanWithoutCallStack` in `hs-opentelemetry/api/src/OpenTelemetry/Trace/Core.hs`. When a new span is created the tracer provider's sampler is called with the parent `Context`, the new `TraceId`, the span name, and the `SpanArguments`. Three outcomes are possible:

- `Drop` — the span is never instantiated. No processor sees it. The returned handle is a `Dropped` value that still carries the trace/span context so child operations can be linked upstream, but recording calls on it are no-ops.
- `RecordOnly` — the span *is* created and is visible to span processors (via `spanProcessorOnStart` and `spanProcessorOnEnd`), but the `sampled` flag in `traceFlags` is not set. Exporters that honor the flag will skip it; processors doing their own filtering (for example metrics derived from spans) can still observe it.
- `RecordAndSample` — the span is created and the `sampled` flag is set. This is the normal "collect this span" path.

Because the decision is made at span start, the sampler has access only to the parent context and the initial attributes passed via `SpanArguments`. It does not see any attribute you add later with `addAttribute`, and it does not see the span's children or its duration. That is what "head only" means in practice.

### Built-in Samplers

All defined in `OpenTelemetry.Trace.Sampler`:

- `alwaysOn` — every span is `RecordAndSample`. The default in development.
- `alwaysOff` — every span is `Drop`. Useful for tests or for disabling tracing globally without tearing down the provider.
- `traceIdRatioBased :: Double -> Sampler` — deterministic ratio sampler that makes its decision from the high bits of the `TraceId`. Because the decision depends only on the trace id, every service that uses `traceIdRatioBased` with the same ratio agrees on whether to sample a given trace, provided they see the same trace id. When a span is sampled, the sampler adds a `sampleRate` attribute equal to `1 / ratio`, which downstream systems can use to scale counts back up.
- `parentBased :: ParentBasedOptions -> Sampler` — a composite that dispatches to one of five delegate samplers based on the parent:
  - `rootSampler` — no parent (the trace starts here).
  - `remoteParentSampled` / `remoteParentNotSampled` — parent came in via an injected header (e.g. from an upstream service).
  - `localParentSampled` / `localParentNotSampled` — parent is a span created in this same process.
  - Build options with `parentBasedOptions :: Sampler -> ParentBasedOptions` and override individual fields. The default for all four "parent present" branches is to honor the incoming `sampled` bit (sampled parents → `alwaysOn`, unsampled parents → `alwaysOff`); you only supply the `rootSampler`.

### The Canonical Configuration

For almost every application the right shape is "ratio-sample at the edge, honor the parent decision everywhere else":

```haskell
import OpenTelemetry.Trace.Sampler

appSampler :: Sampler
appSampler = parentBased (parentBasedOptions (traceIdRatioBased 0.05))
```

This samples 5% of traces that originate in this service and respects the decision of any upstream service for traces it receives. Pass it via `tracerProviderOptionsSampler` when constructing the tracer provider — see `OpenTelemetry-TracerProvider-Guide.md` for the full setup.

Two things worth noting:

1. **Consistency across services.** If every service uses `parentBased` + `traceIdRatioBased`, you will never see "half-sampled" traces — every span in a trace is either kept or dropped together, because the decision is made once at the root and propagated. Mixing in services that use `alwaysOn` breaks this and produces partial traces that are worse than no trace at all.
2. **`traceIdRatioBased` ignores the parent.** That is the whole point of wrapping it in `parentBased` — the ratio sampler is meant to be used only at roots. Using `traceIdRatioBased` directly as the tracer provider's sampler will re-sample independently at every service boundary and break consistency.

### The RecordOnly Escape Hatch

`RecordOnly` is an awkward middle ground and most applications should ignore it. The cases where it's useful:

- You want spans to be visible to a metrics-generating span processor (e.g. one that emits RED metrics derived from span durations) but you do not want them exported as traces.
- You are building a diagnostic workflow where a sidecar reads completed spans and makes its own decision.

If you don't have a concrete use for `RecordOnly`, stick to `Drop` and `RecordAndSample`. Mixing in `RecordOnly` makes it hard to reason about what reaches your backend.

## Tail Sampling

Tail sampling gives you much better retained traces than ratio sampling — you keep the errors and the slow requests instead of a random 5% — but it has to buffer spans long enough to make a trace-wide decision. The `hs-opentelemetry` SDK does not do this, and it is not going to: tail sampling belongs in infrastructure that can hold state across many application instances.

### The Recommended Approach: OpenTelemetry Collector

Run an OpenTelemetry Collector between your Haskell application and your tracing backend, and configure its `tail_sampling` processor. Your application exports everything with `alwaysOn` (or a very permissive head sampler, such as `traceIdRatioBased 1.0` with environment-based overrides), and the Collector decides per-trace what to forward.

A minimal Collector config (`otelcol-contrib` or `otelcol-k8s` — the `tail_sampling` processor is in the contrib distribution):

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    expected_new_traces_per_sec: 1000
    policies:
      - name: keep-errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: keep-slow
        type: latency
        latency:
          threshold_ms: 2000
      - name: keep-sample
        type: probabilistic
        probabilistic:
          sampling_percentage: 5

exporters:
  otlp:
    endpoint: your-backend:4317

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [tail_sampling]
      exporters: [otlp]
```

The `decision_wait` is the key parameter: it is how long the Collector buffers a trace before deciding. Any span that arrives after `decision_wait` for a trace whose decision has already been made will be evaluated against the cached decision if `num_traces` still has it, and otherwise dropped. Set it above the p99 duration of your traces plus export latency; if you set it too low you'll get truncated traces.

Two operational notes that bite people:

1. **All spans from a trace must land on the same Collector instance.** Tail sampling cannot work across Collector replicas because each would only see part of the trace. When you scale out, put a `loadbalancing` exporter in front of the tail-sampling Collectors, keyed on trace id. This is standard practice and well-documented upstream.
2. **Your application's throughput into the Collector is now the full unsampled volume.** Size the network path and the Collector's memory accordingly — `num_traces` × average spans-per-trace × average span size is the steady-state buffer.

If you are using a managed tracing vendor (Honeycomb, Datadog, etc.) check whether they offer equivalent functionality server-side. Honeycomb's "refinery" and Datadog's ingestion sampling are purpose-built tail samplers; you may not need a Collector at all.

### Approximating Tail Sampling In-Process

There is a middle ground: wrap your span processor so it inspects each span at `onEnd` and drops the ones you don't care about. This is described in `OpenTelemetry-BatchProcessor-Filtering-Guide.md` as the "filtering processor wrapper" pattern:

```haskell
filteringProcessor :: (ImmutableSpan -> Bool) -> SpanProcessor -> SpanProcessor
filteringProcessor shouldProcess wrapped = SpanProcessor
  { spanProcessorOnStart = spanProcessorOnStart wrapped
  , spanProcessorOnEnd = \spanRef -> do
      span <- readIORef spanRef
      when (shouldProcess span) $
        spanProcessorOnEnd wrapped spanRef
  , spanProcessorShutdown = spanProcessorShutdown wrapped
  , spanProcessorForceFlush = spanProcessorForceFlush wrapped
  }
```

You can use this to keep only errored spans, or only spans slower than a threshold, while head-sampling everything:

```haskell
keepInterestingSpans :: ImmutableSpan -> Bool
keepInterestingSpans s =
  isError s || durationMs s > 500
```

This is useful and cheap, but it is **not** tail sampling. The critical limitation: in OpenTelemetry a child span is ended *before* its parent, so when `onEnd` fires for a child you do not yet know whether the parent will end in an error state. Per-span filtering can drop individual uninteresting spans, but it cannot express "keep the whole trace iff the root span errored" — you'd need to buffer all of a trace's spans until the root ends, at which point you have reimplemented (badly) what the Collector already does.

Use the filtering processor for coarse, per-span decisions that do not depend on trace-wide context — dropping health-check spans, dropping internal spans below a name prefix, enforcing PII policies. Reach for the Collector the moment your policy involves "look at the whole trace".

### Choosing an Approach

| Need                                                       | Use                                                      |
|------------------------------------------------------------|----------------------------------------------------------|
| Cut volume uniformly, cheap                                | `parentBased (parentBasedOptions (traceIdRatioBased r))` |
| Never sample a specific noisy path                         | Custom head sampler or filtering processor               |
| Always keep errors/slow requests, sample the rest          | OTel Collector with `tail_sampling` processor            |
| Drop individual uninteresting spans (not whole traces)     | Filtering span processor wrapper                         |
| Vendor backend that does its own tail sampling             | `alwaysOn` in the app, let the backend decide            |

A common production shape for a high-volume service:

- `alwaysOn` in each service, so nothing is decided in the app.
- Filtering processor to drop health checks and other known-uninteresting spans before they hit the wire.
- Collector with `tail_sampling` in front of the backend, configured to keep all errors, all slow traces, and a small probabilistic baseline.

## Related Guides

- `OpenTelemetry-Custom-Sampler-Guide.md` — how to write a `Sampler`, including name-based, attribute-based, and composite patterns.
- `OpenTelemetry-TracerProvider-Guide.md` — how to wire the sampler into the tracer provider via `tracerProviderOptionsSampler`.
- `OpenTelemetry-BatchProcessor-Filtering-Guide.md` — the filtering span processor pattern in depth.
- `OpenTelemetry-Propagators-Guide.md` — how the `sampled` flag travels between services.
