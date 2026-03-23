# OpenTelemetry TracerProvider Guide

The TracerProvider is a core component in OpenTelemetry's tracing system. It's responsible for creating Tracers, which in turn are used to create and manage Spans.

## Key Types and Interfaces

### Core Types

- `TracerProvider`: The main interface for creating and managing Tracers.
  - Type: `data TracerProvider`
  - Purpose: Creates and manages tracers, handles span processing, ID generation, and sampling decisions.

- `Tracer`: Used to create spans and manage tracing sessions.
  - Type: `data Tracer`
  - Purpose: Primary entry point for instrumentation code to create spans.

- `TracerProviderOptions`: Configuration options for creating a TracerProvider.
  - Type: `data TracerProviderOptions = TracerProviderOptions {...}`
  - Fields:
    - `tracerProviderOptionsIdGenerator`: Controls trace and span ID generation
    - `tracerProviderOptionsSampler`: Determines which spans to sample
    - `tracerProviderOptionsResources`: Provides application metadata
    - `tracerProviderOptionsAttributeLimits`: Sets attribute limitations
    - `tracerProviderOptionsSpanLimits`: Controls span count and behavior limits
    - `tracerProviderOptionsPropagators`: Defines context propagation mechanisms

### Supporting Types

- `SpanProcessor`: Receives span data and handles it (e.g., batching, exporting).
  - Common implementations: `SimpleSpanProcessor`, `BatchSpanProcessor`

- `IdGenerator`: Generates trace and span IDs.
  - Interface: `IdGenerator`
  - Default implementation: `defaultIdGenerator`

- `Sampler`: Determines which spans should be sampled and recorded.
  - Type: `data Sampler`
  - Common samplers: `alwaysOn`, `alwaysOff`, `traceIdRatioBased`

- `MaterializedResources`: Contains resource attributes describing the service.
  - Type: `data MaterializedResources`

## Key Functions

### TracerProvider Management

- `createTracerProvider :: [SpanProcessor] -> TracerProviderOptions -> IO TracerProvider`
  - Creates a new TracerProvider with custom configuration.

- `initializeGlobalTracerProvider :: IO TracerProvider`
  - Initializes and sets the global TracerProvider with environment configuration.

- `initializeTracerProvider :: IO TracerProvider`
  - Creates a TracerProvider from environment variables without making it global.

- `getGlobalTracerProvider :: IO TracerProvider`
  - Retrieves the globally registered TracerProvider.

- `setGlobalTracerProvider :: TracerProvider -> IO ()`
  - Sets the global TracerProvider for the application.

- `shutdownTracerProvider :: TracerProvider -> IO ()`
  - Gracefully shuts down a TracerProvider, flushing any pending spans.

### Tracer Creation and Usage

- `makeTracer :: TracerProvider -> InstrumentationLibrary -> TracerOptions -> Tracer`
  - Creates a new Tracer from a TracerProvider with the given instrumentation library info. This is a pure function.



## TracerProvider Overview

The TracerProvider handles:

- Processing spans through SpanProcessors
- Generating trace and span IDs via an IdGenerator
- Determining which spans to sample via a Sampler
- Providing application resources/metadata via MaterializedResources
- Setting limits for attributes and spans
- Managing propagation of trace context across service boundaries

## Accessing the TracerProvider

There are several ways to access a TracerProvider:

### 1. Using the global provider

```haskell
tracerProvider <- getGlobalTracerProvider
```

### 2. Initializing a provider with environment variable configuration

```haskell
-- Sets up and makes global
tracerProvider <- initializeGlobalTracerProvider

-- Or set up without making global
tracerProvider <- initializeTracerProvider  
```

### 3. Creating a custom provider

```haskell
tracerProvider <- createTracerProvider processors options
```

## Basic Setup Pattern

```haskell
main :: IO ()
main = withTracer $ \tracer -> do
  -- your application code here
  pure ()
  where
    withTracer f = bracket
      -- Install the SDK, pulling configuration from the environment
      initializeGlobalTracerProvider
      -- Ensure that any spans that haven't been exported yet are flushed
      shutdownTracerProvider
      (\tracerProvider -> do
        -- Get a tracer so you can create spans
        tracer <- pure $ makeTracer tracerProvider $(detectInstrumentationLibrary) tracerOptions
        f tracer
      )
```

## Complete Example

```haskell
import OpenTelemetry.Context
import OpenTelemetry.Trace
import OpenTelemetry.Trace.Core
import OpenTelemetry.Trace.Sampler

main :: IO ()
main = do
  -- Create a custom tracer provider
  let sampler = traceIdRatioBased 0.5  -- Sample 50% of traces
      options = TracerProviderOptions
        { tracerProviderOptionsIdGenerator = defaultIdGenerator
        , tracerProviderOptionsSampler = sampler
        , tracerProviderOptionsResources = mempty
        , tracerProviderOptionsAttributeLimits = defaultAttributeLimits
        , tracerProviderOptionsSpanLimits = defaultSpanLimits
        , tracerProviderOptionsPropagators = []
        }
  
  -- Create a batch span processor with the OTLP exporter
  exporterConfig <- loadExporterEnvironmentVariables
  exporter <- otlpExporter exporterConfig
  processor <- batchProcessor batchTimeoutConfig exporter
  
  -- Create and use the tracer provider
  tracerProvider <- createTracerProvider [processor] options
  let tracer = makeTracer tracerProvider $(detectInstrumentationLibrary) tracerOptions
    
    -- Create spans with the tracer
  inSpan tracer "main-operation" defaultSpanArguments $ do
    -- Your application code here
    pure ()

  shutdownTracerProvider tracerProvider
```

## Environment Variable Configuration

The TracerProvider can be configured via environment variables:

- `OTEL_SDK_DISABLED` - Disable the SDK for all signals
- `OTEL_RESOURCE_ATTRIBUTES` - Key-value pairs for resource attributes
- `OTEL_SERVICE_NAME` - Sets the service.name resource attribute
- `OTEL_PROPAGATORS` - Propagators to use (comma-separated list)
- `OTEL_TRACES_SAMPLER` - Sampler to use for traces
- `OTEL_TRACES_SAMPLER_ARG` - Sampler argument
- `OTEL_TRACES_EXPORTER` - Exporter to use for traces

Batch processor configuration:
- `OTEL_BSP_SCHEDULE_DELAY` - Delay between exports
- `OTEL_BSP_EXPORT_TIMEOUT` - Max export time
- `OTEL_BSP_MAX_QUEUE_SIZE` - Maximum queue size
- `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` - Maximum batch size

Attribute/span limits:
- `OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT` - Max attribute value size
- `OTEL_ATTRIBUTE_COUNT_LIMIT` - Max span attribute count
- `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT` - Max span attribute count
- `OTEL_SPAN_EVENT_COUNT_LIMIT` - Max span event count
- `OTEL_SPAN_LINK_COUNT_LIMIT` - Max span link count

## Custom Configuration

You can create a TracerProvider with custom configuration:

```haskell
tracerProvider <- createTracerProvider 
  [myCustomSpanProcessor] 
  TracerProviderOptions
    { tracerProviderOptionsIdGenerator = defaultIdGenerator
    , tracerProviderOptionsSampler = sampler
    , tracerProviderOptionsResources = resources
    , tracerProviderOptionsAttributeLimits = attrLimits
    , tracerProviderOptionsSpanLimits = spanLimits
    , tracerProviderOptionsPropagators = propagators
    }
```

## Common Samplers

```haskell
-- Always sample every trace
alwaysOn :: Sampler

-- Never sample any traces
alwaysOff :: Sampler

-- Sample a percentage of traces based on trace ID
traceIdRatioBased :: Double -> Sampler

-- Sample based on parent span's sampling decision
parentBased :: ParentBasedOptions -> Sampler
```

## Getting a Tracer

Once you have a TracerProvider, you can get a Tracer to create spans:

```haskell
let tracer = makeTracer tracerProvider $(detectInstrumentationLibrary) tracerOptions
```

### Tracer Names

The tracer name serves several important purposes:

1. **Identification**: It identifies the source of spans in your telemetry data
2. **Organization**: It helps organize and filter traces in visualization tools
3. **Context**: It provides context about which component/library created each span

The tracer name should typically reflect the library, module, or component being instrumented. For example:

- Database client: `"myapp.database"` or `"postgres-client"`
- HTTP server: `"myapp.http.server"` or `"wai-middleware"`
- Background job: `"myapp.jobs.processor"`

When instrumenting a third-party library, you should use a name that clearly identifies that library.

This name appears in your telemetry data and helps operators understand which parts of your application are generating specific traces.

## Cleanup

Remember to shut down the TracerProvider when your application finishes:

```haskell
shutdownTracerProvider tracerProvider
```

This ensures any pending spans are flushed to exporters.

## Best Practices

1. **Use a single TracerProvider**: Generally, only one TracerProvider should be active in an application.

2. **Manage resources properly**: Always use `bracket` or equivalent to ensure proper shutdown.

3. **Use meaningful tracer names**: The tracer name should reflect the library or module being instrumented.

4. **Configure sampling appropriately**: Adjust sampling rates based on your observability needs and traffic volume.

5. **Set appropriate resource attributes**: Include information like service name, version, and deployment information.
