# hs-opentelemetry 1.0 — internal upgrade guide

A condensed view of what is shipping in `hs-opentelemetry` 1.0.0.0 and how
to move our services and libraries onto it. This document **synthesizes**
the upstream changelogs and migration guide — it does not replace them. For
exact wording, citations, and edge cases, consult the upstream sources
linked at the bottom.

> **Heads-up for anyone who tracked the internal "0.4" branch:** 1.0.0.0 is
> the same body of work (module renames, metrics, the C/CMM hot path, the
> `Sampler` ADT, unboxed `TraceId`) released upstream under a 1.0 version,
> plus several changes that branch never had — runtime `Resource` schema,
> the `Context` slot model with replacing `insertBaggage`, `Token`-based
> attach/detach, `SamplingDecision` as the sampler return type, a unified
> SDK entry point, gRPC for all three signals, and the X-Ray propagator.
> The old `OpenTelemetry-0.4-Upgrade-Guide.md` is retired — use this one.

## TL;DR

- **Everything goes to `1.0.0.0`.** `hs-opentelemetry-api`,
  `-sdk`, `-api-types`, `-otlp`, the OTLP/handle/in-memory/Prometheus
  exporters, and the propagators all move to `1.0.0.0` together.
  `hs-opentelemetry-semantic-conventions` is versioned to the spec it
  tracks: **`1.40.0.0`**.
- **Spec conformance is now full against OTel 1.55.0** for the API, and
  semantic conventions track **1.40**.
- Two module namespaces are renamed: `OpenTelemetry.Logs.*` → `Log.*`,
  `OpenTelemetry.Metrics.*` → `Metric.*` (no shims; see the table below).
- A new leaf package, **`hs-opentelemetry-api-types`**, holds `Attribute`
  and `AttributeKey`. Re-exported from the API; only direct consumers of
  those types or the semantic-conventions package need to know.
- **All three signals are complete.** Metrics gains the full synchronous +
  asynchronous instrument surface, views, exemplars, and exponential
  histograms. Logs gains simple/batch processors and OTLP/handle/in-memory
  exporters. A new **`OpenTelemetry.SDK.withOpenTelemetry`** initializes all
  three from `OTEL_*` env vars in one call.
- The trace hot path is rewritten in C and CMM. `inSpan` no-op drops from
  ~316 ns / 1.6 KB to ~14 ns / 15 B; a bare create+end span drops from
  ~593 ns to ~441 ns. Bare span create+end (209 ns) is now faster than the
  Go and Rust SDKs on the equivalent workload.
- Several long-standing correctness bugs are fixed, some of them **silent
  behaviour changes** — `addAttributes` argument order, `setStatus` merge,
  atomic provider swaps, `isValid` requiring both IDs, post-`endSpan`
  mutations dropped. See [Operational changes to watch](#operational-changes-to-watch).
- **Simple span/log processors now export synchronously**, matching every
  other OpenTelemetry SDK. Anything relying on the old unbounded async queue
  should switch to a batch processor before deploying.

Estimated effort per service: ~10–30 minutes if you only consume the
high-level API (`inSpan`, `addAttribute`, exporter wiring). Several hours if
you have custom samplers, processors, exporters, propagators, or low-level
context code.

## Why we want this

1. **Full spec conformance (1.55.0).** The API is now audited against the
   current spec — context, baggage, sampling, status merge, propagation
   fields, and lifecycle rules all match what collectors and other SDKs
   expect.
2. **Metrics.** First-class metrics instead of side-channelling through
   `gauge`/`counter` ad-hoc emit. The API is feature-complete against the
   spec and the SDK has a periodic reader, views, exemplar capture, and
   Prometheus + OTLP exporters.
3. **Logs export.** 0.3 shipped the logs *API* but no exporters. 1.0 ships
   simple and batch `LogRecordProcessor`s plus OTLP / handle / in-memory log
   exporters, so structured logs correlate with traces out of the box.
4. **Allocation / latency.** The traced-no-op cost is now ~14 ns. Coupled
   with the synchronous simple processor and the fixed batch-processor
   force-flush, our trace fan-out should measurably improve under load.

## Spec highlights — what to start using

The whole point of tracking 1.55.0 is the new capabilities. These are the
ones worth adopting deliberately once a service is on 1.0.

### One-call SDK initialization

`OpenTelemetry.SDK` is the recommended entry point. It wires up all three
providers from the standard `OTEL_*` env vars, installs them as globals, and
hands back a single shutdown handle:

```haskell
import OpenTelemetry.SDK

main :: IO ()
main = withOpenTelemetry $ \otel -> do
  tracer <- getTracer (otelTracerProvider otel) "my-app" tracerOptions
  -- otelMeterProvider, otelLoggerProvider, and otelPropagators are also
  -- available on `otel`; otelShutdown flushes and tears all three down.
  runApp tracer
```

`OTelSignals` carries `otelTracerProvider`, `otelMeterProvider`,
`otelLoggerProvider`, `otelPropagators`, and `otelShutdown`. Use
`initializeOpenTelemetry`/`otelShutdown` directly if you manage your own
bracket. (`OTelComponents` is a deprecated alias for `OTelSignals`.)

### Metrics (new signal)

- Synchronous: `Counter`, `UpDownCounter`, `Histogram`, `Gauge` (each
  `Int64` / `Double`).
- Asynchronous: `ObservableCounter`, `ObservableUpDownCounter`,
  `ObservableGauge`, each with an `*Enabled :: IO Bool` so callbacks are
  skipped when no SDK is installed, plus an `ObservableCallbackHandle` for
  unregistration.
- `View` selection and `name`/`description` overrides;
  `filterAttributesByKeys` for attribute projection.
- Exemplars on every data-point type; exponential histograms;
  `AggregationTemporality` (delta / cumulative); `AdvisoryParameters`.
- Cardinality overflow under `otel.metric.overflow=true`.
- Env vars wired: `OTEL_METRICS_EXEMPLAR_FILTER`,
  `OTEL_METRIC_EXPORT_INTERVAL`, `OTEL_METRICS_EXPORTER`.
- Exporters: OTLP, handle, in-memory, and **Prometheus** (new).
- `OpenTelemetry.Debug.MetricExport` renders export batches for debugging.

Start with one well-scoped meter per service and move anything we currently
smuggle through logs/spans onto real instruments. `ghc-metrics` exposes GHC
RTS stats as metrics for free.

### Logs export

- SDK ships `SimpleLogRecordProcessor` and `BatchLogRecordProcessor`.
- Exporters: OTLP (HTTP + gRPC), handle, in-memory.
- `loggerIsEnabled` lets bridges skip work when no processor is registered.
- `eventName` field on `LogRecordArguments`; runtime severity knobs
  (`setLoggerMinSeverity` / `getLoggerMinSeverity`).
- Logging bridges (`katip`, `co-log`, `monad-logger`) route through this.

`BatchLogRecordProcessor` + the OTLP exporter mirrors what we do for spans.

### Per-span exception classification

`OpenTelemetry.Trace.ExceptionHandler` classifies a thrown exception as
`ErrorException` (default), `RecordedException`, or `IgnoredException`, with
optional extra attributes. Install handlers per-`Tracer` via
`tracerExceptionHandlerOptions` or globally via
`tracerProviderOptionsExceptionHandlers`. Smart constructors:
`ignoreExceptionType`, `ignoreExceptionMatching`, `recordExceptionType`,
`recordExceptionMatching`, `classifyException`, and the built-in
`exitSuccessHandler` (ignores `ExitSuccess`). `inSpan` consults them before
setting Error status, so e.g. a `ServantErr 3xx` thrown for control flow no
longer paints spans red.

### Global propagator + new propagators

- Global API: `getGlobalTextMapPropagator` / `setGlobalTextMapPropagator`.
  The SDK sets it during initialization; instrumentation should prefer it
  over reading the propagator off the `TracerProvider`.
- Carrier type is now `TextMap` / `TextMapPropagator` (was
  `RequestHeaders`), dropping `http-types`/`case-insensitive` from the API.
- New propagator packages: **`hs-opentelemetry-propagator-jaeger`**
  (`uber-trace-id`, `uberctx-*` baggage) and
  **`hs-opentelemetry-propagator-xray`** (`X-Amzn-Trace-Id`).

### gRPC OTLP for all three signals

The OTLP exporter can speak gRPC for traces, metrics, **and** logs when the
`grpc` Cabal flag is enabled, plus `otlpConcurrentExports` /
`OTEL_EXPORTER_OTLP_CONCURRENT_EXPORTS` for parallel export.

### Typed semantic conventions (1.40)

`hs-opentelemetry-semantic-conventions` is now **fully auto-generated** from
the upstream YAML model and versioned to the spec it tracks (**1.40.0.0**).
One module, `OpenTelemetry.SemanticConventions`, exports ~900 typed
attribute keys and value enums (http, db, messaging, rpc, network,
server/client, url, code, cloud, k8s, host, process, faas, …). It depends
only on `hs-opentelemetry-api-types`, so libraries that just declare keys
can pull it in without the full API.

```haskell
import qualified OpenTelemetry.SemanticConventions as SC

addAttributes span
  [ SC.http_request_method      .= ("GET" :: Text)
  , SC.http_response_statusCode .= (200 :: Int)
  , SC.server_address           .= host
  ]
```

Same wire format as the old `Text` literals, but typos become compile errors
and the IDE completes keys. Opt-in — string literals still work — so it is
not a release blocker, but it is the cheapest correctness win in the release.

### Baggage size enforcement and W3C Level 2 flags

- `Baggage.insertChecked` enforces the W3C limits (8192 bytes total, 4096
  per member, 180 members). Use it on inbound paths from untrusted sources.
- `TraceFlags` gains W3C Level 2 ops: `isRandom`, `setRandom`, `unsetRandom`.

## Module renames

Repo-wide sed handles the namespace moves:

| Old | New |
|-----|-----|
| `OpenTelemetry.Logs.Core` | `OpenTelemetry.Log.Core` |
| `OpenTelemetry.Internal.Logs.Core` | `OpenTelemetry.Internal.Log.Core` |
| `OpenTelemetry.Internal.Logs.Types` | `OpenTelemetry.Internal.Log.Types` |
| `OpenTelemetry.Internal.Metrics.Types` | `OpenTelemetry.Internal.Metric.Types` |
| `OpenTelemetry.Internal.Metrics.Export` | `OpenTelemetry.Internal.Metric.Export` |
| `OpenTelemetry.Metrics` | `OpenTelemetry.Metric.Core` |
| `OpenTelemetry.Metrics.InstrumentName` | `OpenTelemetry.Metric.InstrumentName` |

## Breaking API changes (by area)

The detailed entries live in the upstream
[migration guide][upstream-migration] and each package's `ChangeLog.md`.
This is the map.

### Tracing

- **`Sampler` is an ADT** (`AlwaysOnSampler`, `AlwaysOffSampler`,
  `TraceIdRatioSampler`, `ParentBasedSampler`, `AlwaysRecordSampler`,
  `CustomSampler`). Smart constructors (`alwaysOn`, `alwaysOff`,
  `traceIdRatioBased`, `parentBased`, `alwaysRecord`) still work. Custom
  samplers change: use `CustomSampler "desc" fn`, `fn` gains a final
  `InstrumentationLibrary` parameter, and it returns a `SamplingDecision`
  record (`samplingOutcome` / `samplingAttributes` / `samplingTraceState`)
  instead of a `(SamplingResult, AttributeMap, TraceState)` tuple. See the
  [Custom Sampler guide](OpenTelemetry-Custom-Sampler-Guide.md).
  `traceIdRatioBased` now uses the low 63 bits of the trace ID (matching
  Go/Java/Python) and its description always follows
  `TraceIdRatioBased{ratio}`.
- **`TraceId` / `SpanId` are unboxed `Word64`s** (was `ShortByteString`).
  Use `traceIdBytes` / `spanIdBytes` / `bytesToTraceId` / `bytesToSpanId`
  for raw bytes; `Base` is now `Base16` only. Hex encoding is unchanged, but
  verify any DB/cache serialization that relied on the internal shape.
- **`Timestamp` is `Word64` nanoseconds** (was `TimeSpec`). Helpers:
  `mkTimestamp`, `timestampToNanoseconds`, `OptionalTimestamp`.
- **`IdGenerator` is an ADT** (`DefaultIdGenerator` / `CustomIdGenerator`).
  Replace the old record with `customIdGenerator mySpanGen myTraceGen`.
- **`Span` is split.** Identity fields are immutable on `ImmutableSpan`;
  mutable state lives behind `spanHot :: IORef SpanHot`. Custom
  `SpanProcessor`s now receive `ImmutableSpan` (not `IORef ImmutableSpan`)
  in `onStart`/`onEnd`.
- **`SpanProcessor` / `SpanExporter` callbacks** return `ShutdownResult` /
  `FlushResult` (was `()` / `Async ShutdownResult`), and `SpanExporter`
  gains a required `spanExporterForceFlush`.
- **`TracerProviderOptions.propagators` is `TextMapPropagator`** (was
  `Propagator Context RequestHeaders RequestHeaders`). New
  `tracerProviderOptionsExceptionHandlers` field.
- **`TracerOptions` is `data`** (was `newtype`), gaining
  `tracerExceptionHandlerOptions`. Use the `tracerOptions` smart constructor.
- **`getTracer` is monadic and cached** — `let tracer = …` becomes
  `tracer <- …`, with a `MonadIO` constraint.
- **`shutdownTracerProvider` takes a `Maybe Int` timeout** (microseconds,
  default 5 s) and returns `ShutdownResult`. It is idempotent. Add the
  argument: `shutdownTracerProvider provider (Just 5_000_000)` (or
  `Nothing` for the default).
- `isValid` now requires **both** trace ID and span ID non-zero.
  `isRecording` returns `False` for `FrozenSpan` / `Dropped`.
- New ergonomics: `alwaysRecord` sampler, `inSpan''` raw variant (skips
  `code.*` attributes), `TraceState.lookup`, W3C `traceparent` codec in
  `OpenTelemetry.Trace.Id` (`encodeTraceparent` / `decodeTraceparent`).

### Context, baggage, propagation

- **`Context` has dedicated unboxed slots** for `Span` and `Baggage`;
  `lookupSpan` is O(1). **Removed exports: `spanKey`, `baggageKey`.**
- **`insertBaggage` now replaces the baggage slot** instead of merging.
  Merge explicitly via the `Semigroup` instance:
  `ctx <> insertBaggage newBaggage Context.empty`.
- **`attachContext` / `detachContext` are `Token`-based** to enforce LIFO:
  `token <- attachContext ctx` … `detachContext token`. A mismatched detach
  logs a warning and still restores. If you used the old returned
  `Maybe Context`, track the previous context yourself. See the
  [Context guide](OpenTelemetry-Context-Guide.md).
- **`propagatorNames` → `propagatorFields`** (returns header names like
  `["traceparent", "tracestate"]`), and custom propagators use the `TextMap`
  carrier (was `RequestHeaders`). `extract`/`inject` now catch and log
  internally.

### Resource

- **The phantom schema type parameter is gone.** `Resource` is now a plain
  record (`resourceSchemaUrl`, `resourceAttributes`); schema merge is a
  runtime warning rather than compile-time. `ToResource` instances lose the
  `ResourceSchema` type synonym, and `materializeResources` is an ordinary
  function. New `materializeResourcesWithSchema` /
  `setMaterializedResourcesSchema` set the runtime schema URL.

### Logs

- `createLoggerProvider` is monadic (`let lp = …` becomes `lp <- …`).
- `loggerIsEnabled :: … -> IO Bool` (was pure); new `loggerIsEnabled'`
  takes severity / event name / `Context`.
- `LogRecordExporter.forceFlush :: IO FlushResult` (was `IO ()`).
- `ReadableLogRecord` is now a true snapshot; `mkReadableLogRecord` is `IO`.
- `shutdownLoggerProvider` is idempotent; emission after shutdown skips
  processors.

### Dependency removals from the API

`random`, `clock`, `http-types`, `case-insensitive`, `binary`, `charset`,
and `regex-tdfa` are **no longer** dependencies of `hs-opentelemetry-api`.
If any of our code pulled these transitively through the API, add them as
direct dependencies.

## Instrumentation: semantic-convention renames

All instrumentation is updated to semconv **1.40**. Stable attribute names
are gated behind `OTEL_SEMCONV_STABILITY_OPT_IN` so dashboards can migrate
independently. Unset = legacy names (default); `<signal>` = stable names;
`<signal>/dup` = both.

```
OTEL_SEMCONV_STABILITY_OPT_IN=http/dup,database,code,messaging
```

The renames that will bite our dashboards:

| Old (default) | Stable | Where |
|---|---|---|
| `http.method` | `http.request.method` | wai, http-client |
| `http.status_code` | `http.response.status_code` | wai, http-client |
| `http.url` | `url.full` | http-client |
| `http.host` | `server.address` | http-client |
| `db.system` | `db.system.name` | postgresql-simple, persistent(-mysql) |
| `db.name` | `db.namespace` | all db |
| `db.statement` | `db.query.text` | postgresql-simple, persistent |
| `db.user` | *(dropped — security)* | postgresql-simple |
| `messaging.operation` | `messaging.operation.name` + `.type` | hw-kafka-client |
| `code.function` + `code.namespace` | `code.function.name` | all spans + log bridges |
| `code.filepath` / `code.lineno` | `code.file.path` / `code.line.number` | all spans + log bridges |
| `http.framework="yesod"` | `webengine.name="yesod"` | yesod |

**Migration strategy:** start with `…/dup` to emit both, update dashboards
and alerts to the stable names, then drop `/dup`, then remove the env var.

## Step-by-step: upgrading an internal service

1. **Bump bounds** in each affected cabal/package.yaml:
   ```yaml
   - hs-opentelemetry-api >= 1.0 && < 1.1
   - hs-opentelemetry-sdk >= 1.0 && < 1.1
   ```
   …and the matching exporter / propagator / instrumentation packages, plus
   any newly-direct deps from [Dependency removals](#dependency-removals-from-the-api).
2. **Rename modules** with a repo-wide sed (`OpenTelemetry.Logs` →
   `OpenTelemetry.Log`, `OpenTelemetry.Metrics` → `OpenTelemetry.Metric`).
   Verify imports compile before any other change.
3. **Consider `withOpenTelemetry`** for app entry points instead of
   hand-wiring providers — it sets the global propagator and gives one
   shutdown handle for all three signals.
4. **`let` → `<-`** for `getTracer`, `createLoggerProvider`, and
   `mkReadableLogRecord` (now monadic); add `MonadIO` where needed.
5. **Add the timeout arg** to every `shutdownTracerProvider` call
   (`(Just 5_000_000)` or `Nothing`).
6. **Audit custom samplers / processors / exporters / propagators** if we
   have any (see [Breaking API changes](#breaking-api-changes-by-area)).
7. **Switch context plumbing** to the `Token` form of `attachContext` /
   `detachContext`, and to `<>` if you relied on `insertBaggage` merging.
8. **Adopt the new signals** — pick a log processor/exporter if emitting log
   records, and stand up one meter per service for metrics.
9. **Run tests → typecheck the app → staging deploy.** The atomicity and
   post-`endSpan` fixes sometimes surface latent misuse that a race used to
   hide.

## Operational changes to watch

Behaviour changes that need no code change but warrant a heads-up before
rollout:

- **Simple processors export synchronously** (`SimpleSpanProcessor.onEnd`,
  `SimpleLogRecordProcessor.onEmit`). Anything pointed at one becomes
  blocking — production should already use batch processors; double-check.
- **`forceFlushTracerProvider` now blocks** until export completes (bounded
  by the export timeout) and no longer leaks async threads on timeout.
- **Batch processor:** synchronous idempotent shutdown/flush (no
  second-call deadlock), bounded power-of-two queue via `unagi-chan`, full
  queues drop silently, warns (doesn't crash) on the non-threaded RTS.
- **`OTEL_SDK_DISABLED=true` still installs propagators** — trace context
  keeps flowing across services even when one is "disabled."
- **`OTEL_SERVICE_NAME` outranks `service.name`** in
  `OTEL_RESOURCE_ATTRIBUTES`. Make sure we don't set both differently.
- **OTLP `Span.flags` / `Link.flags` are now populated.** Collectors doing
  flag-aware sampling (Honeycomb, Datadog, Tempo) will see the real sampled
  bit; validate dashboards that assumed the zero default.
- **NaN/Inf dropped on all numeric instruments; monotonic counters reject
  negatives.** Code emitting these silently no-ops.
- **`addAttributes` now overwrites keys** (the argument order was reversed).
  Code that depended on "keep the first value seen" must reorder.
- **`setStatus` merge follows the spec** (`Ok` final, `Unset` ignored, else
  last-writer-wins); provider globals use `atomicWriteIORef`; span/log
  mutations use `atomicModifyIORef'`; post-`endSpan` mutations are dropped.
- **`isValid` requires both IDs non-zero.** A `SpanContext` with only one ID
  set is now invalid.

## What we don't need to touch yet

- The honeycomb vendor package and the heroku detector have version bumps
  but no API changes that affect us.
- Most propagators (b3, datadog) get bound bumps plus minor correctness
  fixes. If we use them, just bump bounds. (b3 now exposes `b3` and
  `b3multi` as separate registry values.)

## References (upstream)

The authoritative wording lives in the upstream repo. Read these when the
synthesis above is ambiguous:

- **Upstream migration guide** —
  [`hs-opentelemetry/docs/migration-guide.md`][upstream-migration]
- **API changelog** — [`hs-opentelemetry/api/ChangeLog.md`][api-changelog]
- **SDK changelog** — [`hs-opentelemetry/sdk/ChangeLog.md`][sdk-changelog]
- **OTLP / exporter / propagator / instrumentation changelogs** — each
  package has its own `ChangeLog.md` under
  `hs-opentelemetry/{otlp,exporters/*,propagators/*,instrumentation/*}/`.
- **OpenTelemetry spec** —
  [v1.55.0](https://opentelemetry.io/docs/specs/otel/).
- **Semantic conventions** —
  [v1.40](https://opentelemetry.io/docs/specs/semconv/).

[upstream-migration]: ../hs-opentelemetry/docs/migration-guide.md
[api-changelog]: ../hs-opentelemetry/api/ChangeLog.md
[sdk-changelog]: ../hs-opentelemetry/sdk/ChangeLog.md
