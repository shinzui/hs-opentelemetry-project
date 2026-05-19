# hs-opentelemetry 0.4 — internal upgrade guide

A condensed view of what is shipping in `hs-opentelemetry-api` 0.4.0.0 and
the surrounding packages, written for the internal team that will move
services and libraries onto the new release. This document **synthesizes**
the upstream changelogs and migration guide — it does not replace them.
For exact wording, citations, and edge cases, consult the upstream
sources linked at the bottom.

## TL;DR

- One API package (`hs-opentelemetry-api`) goes 0.3.1.0 → **0.4.0.0**;
  every other package moves with it.
- Two module namespaces are renamed: `OpenTelemetry.Logs.*` → `Log.*`,
  `OpenTelemetry.Metrics.*` → `Metric.*` (no shims).
- A new leaf package, **`hs-opentelemetry-api-types`**, holds `Attribute`
  and `AttributeKey`. Re-exported from the API; only direct consumers
  of those types need to know.
- Metrics is finally complete: synchronous and asynchronous instruments,
  views, exemplars, exponential histograms. Logs gets an export pipeline.
- The trace hot path is rewritten in C and CMM. `inSpan` no-op drops
  from ~316 ns / 1.6 KB to ~14 ns / 15 B; a bare active span drops
  from ~593 ns to ~441 ns.
- Spec audit fixes a handful of long-standing correctness bugs
  (`addAttributes` argument order, `setStatus` merge, atomic provider
  swap, batch processor shutdown deadlock, simple processors exporting
  off-thread). Some of these are silent behaviour changes — see
  [Operational changes to watch](#operational-changes-to-watch).
- **Simple span / log processors now export synchronously**, matching
  every other OpenTelemetry SDK. Anything relying on the previous
  unbounded queue should switch to a batch processor before deploying.

Estimated effort per service: ~10–30 minutes if you only consume the
high-level API (`inSpan`, `addAttribute`, exporter wiring). Several
hours if you have custom samplers, processors, exporters, or
log-record code.

## Why we want this

Three things drive the upgrade:

1. **Metrics.** We have been waiting for first-class metrics support
   instead of side-channelling everything through `gauge`/`counter`
   ad-hoc emit. The 0.4 API is feature-complete against the spec and
   the SDK has a periodic reader, views, exemplar capture, and
   Prometheus + OTLP exporters.
2. **Logs export.** 0.3 shipped the logs *API* but no exporters; bridge
   libraries had to be loaded for any output. 0.4 ships simple and
   batch `LogRecordProcessor`s plus OTLP / handle / in-memory log
   exporters.
3. **Allocation / latency.** The traced-no-op cost is now in the
   ~14 ns range. Coupled with the synchronous simple processor and the
   fixed batch-processor force-flush, our existing trace fan-out should
   measurably improve under load.

Spec conformance against 1.55.0 is a bonus — useful to point at when
collectors complain.

## What's in the release (by signal)

This section is a map, not the source of truth. The bullets are the
public changes that will show up in our codebases. Detailed entries
live in each package's `ChangeLog.md`.

### Tracing

Breaking, in approximate order of how likely each is to bite us:

- `OpenTelemetry.Logs.*` → `OpenTelemetry.Log.*`,
  `OpenTelemetry.Metrics.*` → `OpenTelemetry.Metric.*`. Sed-able.
- `Sampler` is now an ADT (`AlwaysOnSampler`, `AlwaysOffSampler`,
  `TraceIdRatioSampler`, `ParentBasedSampler`, `AlwaysRecordSampler`,
  `CustomSampler`). Smart constructors (`alwaysOn`, `parentBased`,
  `traceIdRatioBased`, …) still work; only custom samplers need
  changes. The `shouldSample` callback gains a final
  `InstrumentationScope` parameter.
- `TraceId` and `SpanId` are now unboxed `Word64` pairs (was
  `ShortByteString`). Conversions: `traceIdBytes`, `spanIdBytes`,
  `bytesToTraceId`, `bytesToSpanId`. Hex encoding is unchanged.
- `Timestamp` is now `Word64` nanoseconds (was `TimeSpec`).
- `IdGenerator` is an ADT — use `customIdGenerator span trace` instead
  of the old record constructor.
- `Span` is split: identity fields are immutable; mutable state goes
  through `IORef SpanHot`. Direct field access via the old
  `ImmutableSpan` shape will not compile.
- `SpanProcessor` / `SpanExporter` callbacks return `ShutdownResult`
  and `FlushResult` instead of `()` / `Async ShutdownResult`.
- `SpanExporter` gains a required `spanExporterForceFlush`.
- `TracerOptions` is `data` (was `newtype`) and gains
  `tracerExceptionHandlerOptions`.
- `shutdownTracerProvider` takes a `Maybe Int` timeout and returns
  `ShutdownResult`. Idempotent.
- `getTracer` is monadic and cached; one `Tracer` per scope per
  provider.
- `Context` has dedicated unboxed slots for `Span` and `Baggage`;
  `lookupSpan` is O(1).
- Thread-local `attach`/`detach` is `Token`-based to enforce LIFO.

Net new:

- `OpenTelemetry.Trace.ExceptionHandler` — classify per-span
  exceptions as `Error`/`Recorded`/`Ignored`. Install via
  `tracerExceptionHandlerOptions` or
  `tracerProviderOptionsExceptionHandlers`. Built-in
  `exitSuccessHandler` ignores `ExitSuccess`.
- `OpenTelemetry.Context.Environment` — propagate context to child
  processes via env vars (`TRACEPARENT`, etc.).
- `OpenTelemetry.Context.ThreadLocal.Propagation` — `tracedForkIO`,
  `tracedAsync`, `tracedConcurrently`, … drop-in replacements that
  carry the active context to children.
- `inSpan''` raw variant — skips the automatic `code.*` source-location
  attributes for hot paths.
- `alwaysRecord` sampler — promotes `Drop` to `RecordOnly` so
  processors see every span without inflating export volume.
- `getActiveSpan` / `withActiveSpan` / `getActiveSpanContext`,
  `newEvent` / `newEventWith`, `recordError` — small ergonomic
  helpers we will likely adopt in bridges and middlewares.
- `TraceState.lookup` — spec-required.
- W3C `traceparent` codec in `OpenTelemetry.Trace.Id`
  (`encodeTraceparent`, `decodeTraceparent`).

Bug fixes that change behaviour (silent):

- `addAttributes` now overwrites keys (argument order was reversed).
- `setStatus` merge uses the spec's three rules: `Ok` is final,
  `Unset` ignored, otherwise last-writer-wins.
- `isValid` requires *both* trace ID and span ID non-zero (was
  either).
- `isRecording` returns `False` for `Dropped` / `Frozen` spans.
- `traceIdRatioBased 1.0` no longer collapses to `alwaysOn`'s
  description.
- Post-`endSpan` mutations are silently dropped (spec MUST).
- Provider globals use `atomicWriteIORef`.

### Logs

- `createLoggerProvider` is monadic (`MonadIO m => … -> m LoggerProvider`).
  `let lp = …` becomes `lp <- …`.
- `LogRecordExporter.forceFlush :: IO FlushResult` (was `IO ()`).
- `loggerIsEnabled :: … -> IO Bool` (was pure). New
  `loggerIsEnabled'` takes severity / event name / `Context`.
- `ReadableLogRecord` is a snapshot type; `mkReadableLogRecord` is `IO`.
- New `eventName :: Maybe Text` field on `LogRecordArguments`.
- New runtime knobs: `setLoggerMinSeverity`, `getLoggerMinSeverity`.
- `shutdownLoggerProvider` is idempotent; emission after shutdown
  allocates the record but skips processors.
- SDK ships `SimpleLogRecordProcessor` and `BatchLogRecordProcessor`.
  Exporters: OTLP (HTTP+gRPC), handle, in-memory.

### Metrics (new signal)

- Synchronous: `Counter Int64` / `Counter Double`, `UpDownCounter Int64` /
  `Double`, `Histogram`, `Gauge Int64` / `Double`.
- Asynchronous: `ObservableCounter`, `ObservableUpDownCounter`,
  `ObservableGauge` with `Enabled :: IO Bool` and
  `ObservableCallbackHandle` for unregistration.
- `View` selection by name (wildcard), kind, unit, meter name /
  version / schema URL.
- Exemplars on every data-point type; exponential histograms.
- Cardinality overflow under `otel.metric.overflow=true`.
- `OTEL_METRICS_EXEMPLAR_FILTER`, `OTEL_METRIC_EXPORT_INTERVAL`,
  `OTEL_METRICS_EXPORTER` env vars wired.
- Exporters: OTLP, handle, in-memory, **Prometheus** (new).

### Semantic conventions (now usefully complete)

`hs-opentelemetry-semantic-conventions` was a hand-maintained partial
subset of the spec. In 0.4 it switches to **fully auto-generated** from
the upstream
[semantic-conventions YAML model](https://github.com/open-telemetry/semantic-conventions),
versioned to match the spec it tracks: **1.40.0.0**.

What this means concretely:

- One module — `OpenTelemetry.SemanticConventions` — exports roughly
  900 typed attribute keys and value enums (and grows with every spec
  release).
- Coverage now includes registries we previously had to hand-roll
  attributes for: `http`, `db`, `messaging`, `rpc`, `network`,
  `server` / `client`, `url`, `user_agent`, `code`, `cloud`, `cloudevents`,
  `cloudfoundry`, `k8s` (with `k8s.deprecated`), `host`, `process`,
  `container`, `os`, `device`, `faas`, `feature_flag`, `geo`, `jvm`,
  `go`, `nodejs`, `v8js`, `aspnetcore`, `signalr`, `azure.*`, `oracle_cloud`,
  `heroku`, `hardware` (cpu, fan, battery, memory, network, disk),
  `enduser`, `security_rule`, `source`, `test`, `nfs`, `pprof`,
  `jsonrpc`, `app`, `file`, `webengine`, `opentracing`, …
- Metric definitions (`metric.*` groups) are exported alongside
  attribute definitions. They are documentation today; once we move
  to the metrics API, they give us spec-compliant instrument names
  and units for free.
- The package now depends only on
  `hs-opentelemetry-api-types`, so libraries that only need to
  declare keys (e.g. internal instrumentation packages) can pull in
  semantic-conventions without pulling in the full API or SDK.
- The `dev/generate.hs` executable regenerates the module from the
  YAML model. We can bump the cabal version and re-run when the
  upstream spec advances.

For our internal services: anywhere we hand-write attribute keys as
`Text` literals (`"http.request.method"`, `"db.system.name"`,
`"messaging.system"`, …), replace them with the typed identifiers from
`OpenTelemetry.SemanticConventions`. Same wire format, but typos become
compile errors and the IDE can complete keys for us.

```haskell
import qualified OpenTelemetry.SemanticConventions as SC

addAttributes span
  [ SC.http_request_method  .= ("GET" :: Text)
  , SC.http_response_statusCode .= (200 :: Int)
  , SC.server_address       .= host
  ]
```

This is opt-in — string literals continue to work — so the migration
is not a release blocker. But it is the cheapest correctness win in
the release.

### Context / propagators / baggage

- `Propagator` field `propagatorNames` renamed to `propagatorFields`
  and now returns header names (`["traceparent", "tracestate"]`).
- Global propagator API: `getGlobalTextMapPropagator` /
  `setGlobalTextMapPropagator`. SDK initialization sets it.
- `Baggage.insertChecked` enforces W3C size limits (8192 bytes total,
  4096 per member, 180 members). Use it on inbound paths from
  untrusted sources.
- `SemanticsOptions` is opaque. New `lookupStability key opts`
  generalizes per-signal stability opt-in (HTTP, database, messaging,
  RPC, …) for `OTEL_SEMCONV_STABILITY_OPT_IN`.

### Performance (informational)

| Operation | 0.3.x | 0.4.0.0 |
|---|---|---|
| `inSpan` no-op | 316 ns / 1.6 KB | 14 ns / 15 B |
| `createSpan` no-op | 40 ns / 191 B | 14 ns / 15 B |
| Active bare span | 593 ns / 1.8 KB | 441 ns / 1.1 KB |
| `getContext` | 17 ns | 3 ns |
| `lookupSpan` | 10 ns / 32 B | 0.6 ns / 0 B |

How: thread-local xoshiro256++ ID generator in C, direct
`clock_gettime` FFI, split `Span` representation, flat
open-addressed thread-local context table with two custom CMM
primops (`stg_getCurrentThreadId`, `stg_probeThreadSlot`),
inlined `bracketError`, deferred caller attributes, INLINE audit.
Dropped: `random`, `clock`, `http-types`, `case-insensitive`,
`binary`, `charset`, `regex-tdfa`.

## Step-by-step: upgrading an internal service

The path that has worked when test-upgrading services on a branch:

1. **Bump bounds.** In each affected cabal/package.yaml:
   ```yaml
   - hs-opentelemetry-api >= 0.4 && < 0.5
   - hs-opentelemetry-sdk >= 0.2 && < 0.3
   ```
   …and the matching exporter / propagator / instrumentation
   packages (see the matrix in the upstream
   [migration guide][upstream-migration]).
2. **Rename modules.** A repo-wide sed handles 95 % of it:
   ```
   sed -i 's/OpenTelemetry\.Logs\b/OpenTelemetry.Log/g
           s/OpenTelemetry\.Metrics\b/OpenTelemetry.Metric/g' \
       $(rg -l 'OpenTelemetry\.\(Logs\|Metrics\)')
   ```
   Verify the imports compile before any other change.
3. **Fix logger-provider construction.** Add `<-` where we had `let`:
   ```haskell
   lp <- createLoggerProvider processors options
   ```
4. **Audit custom samplers / processors / exporters** if we have any:
   - Add the `InstrumentationScope` parameter to `CustomSampler`'s
     callback.
   - Add `spanExporterForceFlush` (return `FlushSuccess` if nothing
     to do).
   - Change `SpanProcessor` callbacks to take `ImmutableSpan` instead
     of `IORef ImmutableSpan`.
5. **Switch to the global propagator** in any instrumentation code
   that previously extracted it from the `TracerProvider`:
   ```haskell
   prop <- getGlobalTextMapPropagator
   ```
6. **Pick a log processor / exporter** if we're emitting log records.
   `BatchLogRecordProcessor` with the OTLP exporter mirrors what we
   do for spans.
7. **Adopt the metrics API** for anything we currently smuggle through
   logs/spans. Start with one well-scoped meter scope per service.
8. **Run the test suite, then the typechecker on the application,
   then the staging deploy.** The fixes in this release (atomic
   writes, post-`endSpan` no-mutation) sometimes surface latent
   misuse — a test that always passed because of a race will start
   asserting cleanly.

For services we do not own but instrument (the kafka / persistent /
postgresql-simple / wai-using ones), expect attribute name changes
in stable mode — `db.system → db.system.name`, `db.name → db.namespace`,
`http.host → server.address`, span names becoming low-cardinality. Set
`OTEL_SEMCONV_STABILITY_OPT_IN` per [the spec][semconv-stability] if
the dashboards depend on the legacy keys; pick `database/dup` /
`http/dup` to emit both during the transition.

## Operational changes to watch

Things that change behaviour without a code change being required.
Worth a heads-up in the team channel before rollout.

- **Simple processors export synchronously.** Anything we run a
  `SimpleSpanProcessor` against (probably stdout in dev, in-memory
  in tests) becomes blocking. Production should already use the
  batch processor; double-check.
- **`forceFlushTracerProvider` now blocks until export completes**,
  bounded by `exportTimeoutMillis`. Tests that called it for
  determinism will now actually wait.
- **Batch processor default `maxQueueSize` is 2048**, not 1024.
- **Off-by-one in batch queue capacity fixed.** The queue now holds
  exactly `maxQueueSize` items.
- **`OTEL_SDK_DISABLED=true` still installs propagators.** Trace
  context continues to flow across services even when one of them
  is "disabled."
- **`OTEL_SERVICE_NAME` outranks `service.name` in
  `OTEL_RESOURCE_ATTRIBUTES`.** Make sure we are not setting both
  with different values somewhere in our deployment manifests.
- **OTLP `Span.flags` is now populated.** Collectors doing
  trace-flag-aware sampling (Honeycomb, Datadog, Tempo) will now see
  the real sampled bit. Validate dashboards if any depended on the
  zero default.
- **Monotonic counter rejects negatives, NaN/Inf dropped on all
  numeric instruments.** If we have code that emits these (we
  shouldn't), it will silently no-op.
- **`addAttributes` semantics fixed.** Code that depended on the
  reverse-merge bug to "keep the first value seen" will need to
  reorder its calls.

## What we don't need to touch yet

- The honeycomb vendor package and the heroku detector have version
  bumps but no API changes that affect us.
- Most propagators (b3, datadog, jaeger, xray) only get bound bumps
  plus minor correctness fixes. If we use them at all, just bump
  bounds.

## References (upstream)

The authoritative wording lives in the upstream repo. Read these when
the synthesis above is ambiguous:

- **Upstream migration guide** —
  [`hs-opentelemetry/docs/migration-guide.md`][upstream-migration]
- **API changelog** —
  [`hs-opentelemetry/api/ChangeLog.md`][api-changelog]
- **SDK changelog** —
  [`hs-opentelemetry/sdk/ChangeLog.md`][sdk-changelog]
- **OTLP / exporter / propagator / instrumentation changelogs** —
  each package has its own `ChangeLog.md` under
  `hs-opentelemetry/{otlp,exporters/*,propagators/*,instrumentation/*}/`.
- **PR thread for the API rework** — #252 (the big one), #253 (tests).
- **OpenTelemetry spec** —
  [v1.55.0](https://opentelemetry.io/docs/specs/otel/).
- **Semantic conventions** —
  [v1.40](https://opentelemetry.io/docs/specs/semconv/).

[upstream-migration]: ../hs-opentelemetry/docs/migration-guide.md
[api-changelog]: ../hs-opentelemetry/api/ChangeLog.md
[sdk-changelog]: ../hs-opentelemetry/sdk/ChangeLog.md
[semconv-stability]: https://opentelemetry.io/docs/specs/semconv/non-normative/http-migration/
