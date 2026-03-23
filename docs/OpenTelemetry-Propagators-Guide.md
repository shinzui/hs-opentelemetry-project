# OpenTelemetry Propagators for Haskell

This document explains propagators in the Haskell OpenTelemetry implementation, focusing on their purpose, available implementations, and best usage patterns.

## Table of Contents

- [What are Propagators](#what-are-propagators)
- [Propagator Interface](#propagator-interface)
- [Available Propagators](#available-propagators)
  - [W3C Propagators](#w3c-propagators)
  - [B3 Propagator](#b3-propagator)
  - [Datadog Propagator](#datadog-propagator)
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
  { propagatorNames :: [Text]       -- Names for identification
  , extractor :: inboundCarrier -> context -> IO context  -- Extracts context from inbound carrier
  , injector :: context -> outboundCarrier -> IO outboundCarrier   -- Injects context into outbound carrier
  }
```

The key operations are:

- `extract :: Propagator context i o -> i -> context -> IO context`
  - Extracts context from the inbound carrier (e.g., HTTP headers)

- `inject :: Propagator context i o -> context -> o -> IO o`
  - Injects context into the outbound carrier for transmission

In practice, the propagators in this library use `Propagator Context RequestHeaders RequestHeaders` where `RequestHeaders = [(HeaderName, ByteString)]`.

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
  newCtx <- extract propagator (requestHeaders req) currentCtx
  
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
  propagator <- getTracerProviderPropagator <$> getGlobalTracerProvider
  
  -- Inject context into outgoing request
  headers <- inject propagator ctx []
  let req' = req { requestHeaders = headers ++ requestHeaders req }
  
  -- Make the request with propagated context
  response <- httpLbs req' manager
  pure response
```

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
myCustomPropagator :: Propagator Context [(Text, Text)] [(Text, Text)]
myCustomPropagator = Propagator
  { propagatorNames = ["my-custom-propagator"]
  , extractor = \carrier ctx -> do
      -- Extract implementation
      case lookup "my-header" carrier of
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
          pure $ ("my-header", formattedValue) : carrier
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
