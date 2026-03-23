# OpenTelemetry API and SDK for Haskell

This document explains the architecture and implementation of Haskell's OpenTelemetry API and SDK packages, along with best usage patterns for effective implementation in your applications.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [API Package](#api-package)
  - [Core Components](#core-components)
  - [API Design](#api-design)
  - [Key Interfaces](#key-interfaces)
- [SDK Package](#sdk-package)
  - [Implementation Details](#implementation-details)
  - [Configuration Options](#configuration-options)
  - [Span Processing](#span-processing)
  - [Resource Detectors](#resource-detectors)
- [Best Usage Patterns](#best-usage-patterns)
  - [Initialization](#initialization)
  - [Creating and Managing Spans](#creating-and-managing-spans)
  - [Context Propagation](#context-propagation)
  - [Error Handling](#error-handling)
  - [Middleware Integration](#middleware-integration)
- [Common Instrumentation Patterns](#common-instrumentation-patterns)
  - [Web Frameworks](#web-frameworks)
  - [Database Access](#database-access)
  - [HTTP Clients](#http-clients)
  - [Testing Frameworks](#testing-frameworks)
- [Advanced Topics](#advanced-topics)
  - [Custom Exporters](#custom-exporters)
  - [Sampling Strategies](#sampling-strategies)
  - [Baggage Propagation](#baggage-propagation)

## Architecture Overview

OpenTelemetry for Haskell follows the standard OpenTelemetry architecture of separating API from SDK implementation:

- **API Package**: Defines interfaces and types without implementation
- **SDK Package**: Provides concrete implementations of the API interfaces
- **Instrumentation Packages**: Integrate with common Haskell libraries
- **Exporters**: Send telemetry data to backends
- **Propagators**: Pass context between services

This separation allows libraries to instrument their code without forcing applications to use a specific telemetry backend.

## API Package

The API package defines the core interfaces for tracing without implementation details.

### Core Components

#### Trace API

- **TracerProvider**: Factory for creating tracers
  - Defined in: `api/src/OpenTelemetry/Trace/Core.hs`
  - Functions: `getGlobalTracerProvider`, `setGlobalTracerProvider`
  
- **Tracer**: Creates and manages spans
  - Defined in: `api/src/OpenTelemetry/Trace/Core.hs`
  - Used through `getTracer` from a TracerProvider

- **Span**: Represents a unit of work in a trace
  - Core types defined in: `api/src/OpenTelemetry/Internal/Trace/Types.hs`
  - API defined in: `api/src/OpenTelemetry/Trace/Core.hs`
  - Functions: `createSpan`, `inSpan`, `endSpan`
  - Span manipulation: `addAttribute`, `addEvent`, `setStatus`, `updateName`

#### Context API

- Thread-local storage for propagating spans across services
- Defined in: `api/src/OpenTelemetry/Context.hs` and `api/src/OpenTelemetry/Context/Types.hs`
- Functions: `lookup`, `insert`, `delete`, `empty`
- Special helpers: `insertSpan`, `lookupSpan`, `removeSpan`

#### Baggage API

- Key-value pairs for cross-cutting concerns
- Defined in: `api/src/OpenTelemetry/Baggage.hs`
- Functions: `insert`, `delete`, `empty`, `fromHashMap`
- Encoding/decoding for passing between services

### API Design

The API offers two complementary programming styles:

1. **Low-level Core API**
   - Defined in: `api/src/OpenTelemetry/Trace/Core.hs`
   - Direct access to all functionality
   - More verbose but offers maximum control

2. **Monad-based High-level API**
   - Defined in: `api/src/OpenTelemetry/Trace/Monad.hs`
   - More idiomatic Haskell approach with `MonadTracer` typeclass
   - Simplified interface with `inSpan` in monad stacks

### Key Interfaces

```haskell
-- Create a span and execute an action with it
-- api/src/OpenTelemetry/Trace/Core.hs
inSpan :: (MonadUnliftIO m, HasCallStack) => Tracer -> Text -> SpanArguments -> m a -> m a

-- Monad-based variant for cleaner integration
-- api/src/OpenTelemetry/Trace/Monad.hs
inSpan :: (MonadUnliftIO m, MonadTracer m, HasCallStack) => Text -> SpanArguments -> m a -> m a

-- Adding attributes to spans
-- api/src/OpenTelemetry/Trace/Core.hs
addAttribute :: (MonadIO m, ToAttribute a) => Span -> Text -> a -> m ()
```

## SDK Package

The SDK package implements the API interfaces with full tracing functionality.

### Implementation Details

- **TracerProvider Implementation**: Complete implementation that:
  - Defined in: `sdk/src/OpenTelemetry/Trace.hs`
  - Creates configured tracers
  - Manages span processors
  - Handles resource detection
  - Controls sampling

- **Tracing Pipeline**:
  1. Spans are created via the TracerProvider
  2. Spans are processed by SpanProcessors
  3. Processors send spans to Exporters
  4. Exporters transmit to backend systems

### Configuration Options

The SDK supports extensive configuration through environment variables (processed in `sdk/src/OpenTelemetry/Trace.hs`):

- `OTEL_SDK_DISABLED`: Disables the SDK
- `OTEL_RESOURCE_ATTRIBUTES`: Sets resource attributes
- `OTEL_SERVICE_NAME`: Sets service name
- `OTEL_PROPAGATORS`: Configures propagators
- `OTEL_TRACES_SAMPLER`: Sets sampling strategy
- `OTEL_BSP_*`: Batch processor configuration
- `OTEL_ATTRIBUTE_*`: Attribute limits
- `OTEL_SPAN_*`: Span limits

### Span Processing

Two main processor types are available:

1. **Simple Processor**: Immediately exports each span
   - Defined in: `sdk/src/OpenTelemetry/Processor/Simple/Span.hs`
   - Simpler but less efficient
   - Useful for debugging

2. **Batch Processor**: Batches spans for efficient export
   - Defined in: `sdk/src/OpenTelemetry/Processor/Batch/Span.hs`
   - Configurable batch size and scheduler
   - Recommended for production use
   - Has graceful shutdown capability

### Resource Detectors

Automatic detection of:
- Host information: `sdk/src/OpenTelemetry/Resource/Host/Detector.hs`
- Operating system details: `sdk/src/OpenTelemetry/Resource/OperatingSystem/Detector.hs`
- Process information: `sdk/src/OpenTelemetry/Resource/Process/Detector.hs`
- Service details: `sdk/src/OpenTelemetry/Resource/Service/Detector.hs`
- SDK/telemetry information: `sdk/src/OpenTelemetry/Resource/Telemetry/Detector.hs`

## Best Usage Patterns

### Initialization

Initialize the SDK at application startup:

```haskell
main :: IO ()
main = bracket
  initializeGlobalTracerProvider
  shutdownTracerProvider
  $ \_ -> do
    -- Your application code here
```

For more control over configuration:

```haskell
main :: IO ()
main = do
  exporterConfig <- loadExporterEnvironmentVariables
  exporter <- otlpExporter exporterConfig
  processor <- batchProcessor batchTimeoutConfig exporter
  provider <- createTracerProvider [processor] emptyTracerProviderOptions
    { tracerProviderOptionsSampler = alwaysOn
    }
  setGlobalTracerProvider provider
  
  -- Application code
  
  shutdownTracerProvider provider
```

### Creating and Managing Spans

Basic usage pattern:

```haskell
-- Get a tracer
tracer <- pure $ makeTracer tracerProvider $(detectInstrumentationLibrary) tracerOptions

-- Create spans around operations
result <- inSpan tracer "operation-name" defaultSpanArguments $ do
  -- Your code here
  pure someResult
```

With explicit span manipulation:

```haskell
inSpan' tracer "operation-name" defaultSpanArguments $ \span -> do
  -- Add details to the span
  addAttribute span "user.id" userId
  addEvent span "processing.started" []
  
  -- Your code here
  
  addEvent span "processing.completed" []
```

Using the monad-based API in a monad stack:

```haskell
processRequest :: MonadTracer m => Request -> m Response
processRequest req = inSpan "process-request" defaultSpanArguments $ do
  -- Processing logic
  response <- callService
  pure response
```

#### Understanding Span Kind

OpenTelemetry defines different `SpanKind` values to categorize spans based on their role in the distributed system. The `SpanKind` is specified when creating a span through `SpanArguments`:

```haskell
-- Creating a client span
let clientArgs = defaultSpanArguments { kind = Client }
inSpan tracer "http-request" clientArgs $ do
  -- Make HTTP request

-- Creating a server span
let serverArgs = defaultSpanArguments { kind = Server }
inSpan tracer "handle-request" serverArgs $ do
  -- Process incoming request
```

The available span kinds are:

1. **Internal (default)**: Used for operations that don't cross service boundaries
   ```haskell
   defaultSpanArguments -- defaults to { kind = Internal }
   ```

2. **Server**: Used for handling incoming requests from other services
   ```haskell
   defaultSpanArguments { kind = Server }
   ```

3. **Client**: Used when calling external services
   ```haskell
   defaultSpanArguments { kind = Client }
   ```

4. **Producer**: Used when sending messages to a broker/queue
   ```haskell
   defaultSpanArguments { kind = Producer }
   ```

5. **Consumer**: Used when receiving messages from a broker/queue
   ```haskell
   defaultSpanArguments { kind = Consumer }
   ```

Span kinds help visualize the roles of different components in a distributed trace. They also influence how context propagation works:

- **Client → Server**: Client spans inject context, Server spans extract context
- **Producer → Consumer**: Producer spans inject context, Consumer spans extract context

Using the appropriate span kind ensures correct visualization in tracing UIs and proper automated analysis by observability systems.

### Context Propagation

Propagating context between components:

```haskell
-- Store span in context
ctx <- getContext
let ctx' = insertSpan span ctx
  
-- Run with this context
withContext ctx' $ do
  -- Operations here have access to the span
```

For HTTP requests:

```haskell
-- Extract context from incoming request
ctx <- extractW3C headers

-- Create child span in that context
withContext ctx $
  inSpan tracer "handle-request" defaultSpanArguments $ do
    -- Handle request
    
    -- Inject context into outgoing requests
    headers' <- injectW3C $ getContext
    makeOutgoingRequest headers'
```

### Error Handling

Capturing errors in spans:

```haskell
inSpan tracer "risky-operation" defaultSpanArguments $ do
  result <- try someRiskyOperation
  case result of
    Left err -> do
      setStatus span (Error $ pack $ show err)
      addEvent span "error" [("exception.message", show err)]
      throwIO err
    Right value -> 
      pure value
```

### Middleware Integration

For WAI applications:

```haskell
app :: Application
app = openTelemetryWaiMiddleware middleware $ \req respond -> do
  -- Application logic
```

For Yesod:

```haskell
instance Yesod App where
  -- other instance methods
  
  yesodMiddleware = openTelemetryYesodMiddleware defaultConfig . defaultYesodMiddleware
```

## Common Instrumentation Patterns

### Web Frameworks

```haskell
-- WAI/Warp
-- instrumentation/wai/src/OpenTelemetry/Instrumentation/Wai.hs
app :: Application
app = openTelemetryWaiMiddleware defaultWaiConfig $ \req respond -> do
  -- Application code

-- Yesod
-- instrumentation/yesod/src/OpenTelemetry/Instrumentation/Yesod.hs
yesodMiddleware = openTelemetryYesodMiddleware defaultConfig . defaultYesodMiddleware
```

### Database Access

```haskell
-- For Persistent
-- instrumentation/persistent/src/OpenTelemetry/Instrumentation/Persistent.hs
runDb pool action = do
  -- Wrap the SQL backend with OpenTelemetry instrumentation
  sqlBackend <- wrapSqlBackend <$> createSqlBackend pool
  runSqlWith sqlBackend action

-- For PostgreSQL-Simple
-- instrumentation/postgresql-simple/src/OpenTelemetry/Instrumentation/PostgresqlSimple.hs
withTracing conn query params = do
  traced <- postgresqlSimpleQuery tracer conn
  traced query params
```

### HTTP Clients

```haskell
-- Basic HTTP client instrumentation
-- instrumentation/http-client/src/OpenTelemetry/Instrumentation/HttpClient/Simple.hs
manager <- newManager defaultManagerSettings
tracedManager <- instrumentHttpManager defaultClientConfig manager

-- Make requests with the instrumented manager
httpLbs request tracedManager
```

### Testing Frameworks

```haskell
-- HSpec instrumentation
-- instrumentation/hspec/src/OpenTelemetry/Instrumentation/Hspec.hs
main :: IO ()
main = hspec $ do
  instrumentSpec defaultConfig $ do
    describe "MyModule" $ do
      it "should do something" $ do
        -- Test code
```

## Advanced Topics

### Custom Exporters

The SDK supports different exporters:

```haskell
-- Console exporter for development
-- exporters/handle/src/OpenTelemetry/Exporter/Handle/Span.hs
exporter <- stdoutExporter' defaultFormatter

-- OTLP exporter for production
-- exporters/otlp/src/OpenTelemetry/Exporter/OTLP/Span.hs
exporter <- do { config <- loadExporterEnvironmentVariables; otlpExporter config }

-- In-memory exporter for testing
-- exporters/in-memory/src/OpenTelemetry/Exporter/InMemory/Span.hs
exporter <- inMemoryListExporter
```

### Sampling Strategies

Control which spans are collected:

```haskell
-- Always collect spans
-- api/src/OpenTelemetry/Trace/Sampler.hs
sampler = alwaysOn

-- Collect no spans (for testing/dev)
sampler = alwaysOff

-- Probabilistic sampling
sampler = traceIdRatioBased 0.1 -- 10% of traces

-- Parent-based sampling (inherit from parent span)
sampler = parentBased (parentBasedOptions alwaysOn)
```

### Baggage Propagation

```haskell
-- Create baggage
-- api/src/OpenTelemetry/Baggage.hs
baggage <- empty
baggage' <- insert baggage "user.id" userId

-- Store in context
ctx <- getContext
let ctx' = insertBaggage baggage' ctx

-- Run with this context
withContext ctx' $ do
  -- Later retrieve the baggage
  mbBaggage <- lookupBaggage =<< getContext
  case mbBaggage of
    Just baggage -> do
      let mbUserId = lookup baggage "user.id"
      -- Use the user ID
    Nothing -> 
      -- No baggage available
```

---

This guide provides an overview of the OpenTelemetry API and SDK for Haskell. For more detailed information, refer to the module documentation and examples in the repository.
