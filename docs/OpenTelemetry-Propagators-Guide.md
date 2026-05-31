# OpenTelemetry Propagators for Haskell

This document explains propagators in the Haskell OpenTelemetry implementation, focusing on their purpose, available implementations, and best usage patterns.

## Table of Contents

- [What are Propagators](#what-are-propagators)
- [Propagator Interface](#propagator-interface)
- [Available Propagators](#available-propagators)
  - [W3C Propagators](#w3c-propagators)
  - [B3 Propagator](#b3-propagator)
  - [Datadog Propagator](#datadog-propagator)
  - [Jaeger Propagator](#jaeger-propagator)
  - [AWS X-Ray Propagator](#aws-x-ray-propagator)
- [Usage Patterns](#usage-patterns)
  - [SDK Configuration](#sdk-configuration)
  - [HTTP Server Integration](#http-server-integration)
  - [HTTP Client Integration](#http-client-integration)
  - [Manual Context Propagation](#manual-context-propagation)
- [Composing Propagators](#composing-propagators)
- [Creating Custom Propagators](#creating-custom-propagators)

## What are Propagators

Propagators are components that serialize and deserialize OpenTelemetry context information for transmission across service boundaries. They enable distributed tracing by ensuring that:

1. Trace context is maintained across service calls
2. Baggage information is passed between services
3. Various vendor-specific formats are supported for interoperability

Propagators work with "carriers" - typically HTTP headers, but potentially any structure that can transport key-value pairs between services.

## Propagator Interface

In the Haskell implementation, a `Propagator` consists of:

```haskell
data Propagator context inboundCarrier outboundCarrier = Propagator
  { propagatorFields :: [Text]      -- Header field names the propagator reads/writes (the spec's "Fields")
  , extractor :: inboundCarrier -> context -> IO context  -- Extracts context from inbound carrier
  , injector :: context -> outboundCarrier -> IO outboundCarrier   -- Injects context into outbound carrier
  }
```

> Note: the record field was previously called `propagatorNames`. As of 1.0.0 it
> is named `propagatorFields`, and its values are the actual carrier field
> (header) names the propagator reads and writes — e.g. `["traceparent", "tracestate"]`
> — corresponding to the spec's `Fields`. A deprecated `propagatorNames` accessor
> still exists as an alias but will be removed in a future release.

The key operations are:

- `extract :: Propagator context i o -> i -> context -> IO context`
  - Extracts context from the inbound carrier (e.g., HTTP headers)

- `inject :: Propagator context i o -> context -> o -> IO o`
  - Injects context into the outbound carrier for transmission

In practice, the standard propagator type is the `TextMapPropagator` alias exported from `OpenTelemetry.Propagator`:

```haskell
type TextMapPropagator = Propagator Context TextMap TextMap
```

`TextMap` is a case-insensitive map of `Text` keys to `Text` values (keys compared
case-insensitively while preserving their original casing, matching HTTP header
semantics). It is the only carrier defined by the OpenTelemetry specification.
Instrumentation libraries convert between transport-specific formats (HTTP headers,
gRPC metadata, environment variables, etc.) and `TextMap` at the boundary, then
pass the `TextMap` to the propagator. All built-in propagators in this library are
`TextMapPropagator`s, and the global propagator API operates on `TextMapPropagator`.

`OpenTelemetry.Propagator` provides helpers for working with `TextMap`, including
`emptyTextMap`, `textMapInsert`, `textMapLookup`, `textMapDelete`, `textMapKeys`,
`textMapToList`, and `textMapFromList`. (Earlier versions used
`Propagator Context RequestHeaders RequestHeaders` based on `http-types`; 1.0.0
replaced this with `TextMap` and dropped the `http-types`/`case-insensitive`
dependencies.)

## Available Propagators

### W3C Propagators

The W3C propagators implement the official W3C Trace Context specification:

1. **W3C TraceContext**:
   - Package: `hs-opentelemetry-propagator-w3c`
   - Headers: `traceparent`, `tracestate`
   - Format: `00-<trace-id>-<parent-id>-<trace-flags>`
   - Usage: `w3cTraceContextPropagator`

2. **W3C Baggage**:
   - Package: `hs-opentelemetry-propagator-w3c`
   - Header: `baggage`
   - Format: `key1=value1,key2=value2;property=value`
   - Usage: `w3cBaggagePropagator`

### B3 Propagator

The B3 propagator implements Zipkin's B3 specification:

- Package: `hs-opentelemetry-propagator-b3`
- Two variants:
  - Single-header: `b3TraceContextPropagator` using the `b3` header
  - Multi-header: `b3MultiTraceContextPropagator` using `X-B3-*` headers
- Headers: 
  - Single: `b3: <trace-id>-<span-id>-<sampling>-<parent-span-id>`
  - Multi: `X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`, `X-B3-Flags`, `X-B3-ParentSpanId`

### Datadog Propagator

The Datadog propagator enables interoperability with Datadog APM:

- Package: `hs-opentelemetry-propagator-datadog`
- Usage: `datadogTraceContextPropagator`
- Headers: `x-datadog-trace-id`, `x-datadog-parent-id`, `x-datadog-sampling-priority`
- Handles conversions between OpenTelemetry 128-bit IDs and Datadog 64-bit IDs

### Jaeger Propagator

The Jaeger propagator implements Jaeger's native propagation format:

- Package: `hs-opentelemetry-propagator-jaeger`
- Module: `OpenTelemetry.Propagator.Jaeger`
- Usage:
  - `jaegerPropagator` - trace context plus baggage
  - `jaegerTraceContextPropagator` - the `uber-trace-id` header only (no baggage)
  - `jaegerBaggagePropagator` - `uberctx-*` baggage headers only
- Headers:
  - `uber-trace-id`: `{trace-id}:{span-id}:{parent-span-id}:{flags}`
  - `uberctx-{key}`: one header per baggage entry

### AWS X-Ray Propagator

The X-Ray propagator implements the AWS X-Ray trace header used by ALB, API
Gateway, and other AWS services:

- Package: `hs-opentelemetry-propagator-xray`
- Module: `OpenTelemetry.Propagator.XRay`
- Usage: `xrayPropagator`
- Header: `X-Amzn-Trace-Id`
- Format: `Root=1-{epoch8hex}-{unique24hex};Parent={spanid16hex};Sampled={0|1}`

## Usage Patterns

### SDK Configuration

Propagators are configured during SDK initialization:

```haskell
-- Configure via environment variable
-- OTEL_PROPAGATORS=tracecontext,baggage,b3
main = do
  initializeGlobalTracerProvider

-- Or explicitly during setup
main = do
  let propagator = w3cTraceContextPropagator <> w3cBaggagePropagator
      options = emptyTracerProviderOptions
        { tracerProviderOptionsPropagators = propagator
        }
  provider <- createTracerProvider [] options
  setGlobalTracerProvider provider
```

### HTTP Server Integration

For server middleware like WAI:

```haskell
-- In WAI middleware
middleware app req respond = do
  -- Extract context from request headers
  currentCtx <- getContext
  let propagator = w3cTraceContextPropagator <> w3cBaggagePropagator
      -- Convert transport-specific headers into the TextMap carrier
      carrier = textMapFromList
        [ (decodeUtf8 (CI.original name), decodeUtf8 value)
        | (name, value) <- requestHeaders req
        ]
  newCtx <- extract propagator carrier currentCtx

  -- Use the extracted context for the request
  withContext newCtx $ do
    -- Your application code with the propagated context
    app req $ \response -> do
      -- Response headers can also have context injected if needed
      respond response
```

### HTTP Client Integration

For HTTP client requests:

```haskell
-- In HTTP client code
makeRequest url = do
  req <- parseRequest url
  ctx <- getContext
  -- Prefer the globally configured propagator (set by the SDK at init)
  propagator <- getGlobalTextMapPropagator

  -- Inject context into a TextMap carrier, then convert to request headers
  tm <- inject propagator ctx emptyTextMap
  let injected = [(CI.mk (encodeUtf8 k), encodeUtf8 v) | (k, v) <- textMapToList tm]
      req' = req { requestHeaders = injected ++ requestHeaders req }

  -- Make the request with propagated context
  response <- httpLbs req' manager
  pure response
```

Instrumentation should prefer `getGlobalTextMapPropagator` over reading the
propagator off the `TracerProvider`. If you do need the provider's propagator,
the accessor is `getTracerProviderPropagators` (plural), which returns a
`TextMapPropagator`.

### Manual Context Propagation

For custom protocols or transport mechanisms:

```haskell
-- Extract context from a custom carrier
extractContext :: CustomCarrier -> IO Context
extractContext carrier = do
  currentCtx <- getContext
  extract propagator carrier currentCtx

-- Inject context into a custom carrier
injectContext :: Context -> CustomCarrier -> IO CustomCarrier
injectContext ctx carrier = do
  inject propagator ctx carrier
```

## Composing Propagators

Multiple propagators can be combined using the `Semigroup` instance:

```haskell
-- Combine W3C and B3 propagators
compositePropagator = w3cTraceContextPropagator <> b3TraceContextPropagator

-- Combine multiple propagators
fullPropagator = mconcat
  [ w3cTraceContextPropagator
  , w3cBaggagePropagator
  , b3TraceContextPropagator
  ]
```

When multiple propagators are composed:
- For extraction: All propagators extract in sequence, potentially enriching the context
- For injection: All propagators inject in sequence, potentially adding to the carrier

## Creating Custom Propagators

To create a custom propagator:

```haskell
myCustomPropagator :: TextMapPropagator
myCustomPropagator = Propagator
  { propagatorFields = ["my-header"]   -- The header field names this propagator reads/writes
  , extractor = \carrier ctx -> do
      -- Extract implementation
      case textMapLookup "my-header" carrier of
        Just value -> do
          -- Parse value and update context
          let parsedValue = parseCustomFormat value
          pure $ insertCustomValue parsedValue ctx
        Nothing ->
          pure ctx

  , injector = \ctx carrier -> do
      -- Inject implementation
      case lookupCustomValue ctx of
        Just value -> do
          -- Format value and add to carrier
          let formattedValue = formatCustomValue value
          pure $ textMapInsert "my-header" formattedValue carrier
        Nothing ->
          pure carrier
  }
```

Key considerations for custom propagators:
- Follow the W3C guidelines for header naming and formatting
- Handle errors gracefully - extraction should never fail
- Be efficient with header size (minimize data transferred)
- Support proper composition with other propagators

---

This guide provides an overview of the OpenTelemetry propagator system in Haskell. For more details, refer to the specific propagator package documentation and the OpenTelemetry specification.
