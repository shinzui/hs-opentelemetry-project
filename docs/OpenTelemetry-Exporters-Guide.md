  # OpenTelemetry Exporters for Haskell

This document explains the OpenTelemetry exporter system in Haskell, including available exporters, their configuration, usage patterns, and how to create custom exporters for unsupported backends.

## Table of Contents

- [What are Exporters](#what-are-exporters)
- [Exporter Interface](#exporter-interface)
- [Built-in Exporters](#built-in-exporters)
  - [OTLP Exporter](#otlp-exporter)
  - [Handle Exporter](#handle-exporter)
  - [In-Memory Exporter](#in-memory-exporter)
- [Exporter Usage Patterns](#exporter-usage-patterns)
  - [Configuration via Environment](#configuration-via-environment)
  - [Programmatic Configuration](#programmatic-configuration)
  - [Multiple Exporters](#multiple-exporters)
- [Exporters and Processors](#exporters-and-processors)
  - [Simple Processor](#simple-processor)
  - [Batch Processor](#batch-processor)
- [Creating Custom Exporters](#creating-custom-exporters)
  - [Custom Span Exporter](#custom-span-exporter)
  - [Custom Log Record Exporter](#custom-log-record-exporter)
  - [Best Practices](#best-practices)
- [Testing Exporter Implementations](#testing-exporter-implementations)

## What are Exporters

Exporters are components responsible for sending telemetry data (traces, metrics, logs) to a backend system. They handle:

1. Serializing telemetry data to the appropriate format
2. Sending data to the destination
3. Managing the connection lifecycle
4. Handling export failures and retries

OpenTelemetry separates the collection of telemetry data from its export, allowing applications to switch backends without changing instrumentation code.

## Exporter Interface

The Haskell OpenTelemetry implementation provides two main exporter interfaces:

### Span Exporter

```haskell
data SpanExporter = SpanExporter
  { spanExporterExport :: HashMap InstrumentationLibrary (Vector ImmutableSpan) -> IO ExportResult
  , spanExporterShutdown :: IO ()
  }

data ExportResult
  = Success
  | Failure (Maybe SomeException)
```

### Log Record Exporter

```haskell
data LogRecordExporterArguments = LogRecordExporterArguments
  { logRecordExporterArgumentsExport :: Vector ReadableLogRecord -> IO ExportResult
  , logRecordExporterArgumentsForceFlush :: IO ()
  , logRecordExporterArgumentsShutdown :: IO ()
  }

-- LogRecordExporter provides thread safety guarantees
newtype LogRecordExporter = LogRecordExporter {unExporter :: MVar LogRecordExporterArguments}
```

## Built-in Exporters

### OTLP Exporter

The OpenTelemetry Protocol (OTLP) exporter sends data to the OpenTelemetry Collector or directly to compatible backends:

```haskell
-- Create the OTLP exporter from environment variables
config <- loadExporterEnvironmentVariables
exporter <- otlpExporter config

-- Or with custom config
exporter <- otlpExporter $ OTLPExporterConfig
  { otlpEndpoint = Just "https://collector.example.com:4318"
  , otlpTracesEndpoint = Nothing
  , otlpHeaders = Just [("api-key", "your-api-key")]
  , otlpTracesHeaders = Nothing
  , otlpCompression = Nothing
  , otlpTracesCompression = Nothing
  , otlpTimeout = Nothing
  , otlpTracesTimeout = Nothing
  , otlpProtocol = Nothing
  , otlpTracesProtocol = Nothing
  -- ... other fields default to Nothing/False
  }
```

Configuration options include:
- Endpoints (via `OTEL_EXPORTER_OTLP_ENDPOINT` or `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`)
- Headers (via `OTEL_EXPORTER_OTLP_HEADERS` or `OTEL_EXPORTER_OTLP_TRACES_HEADERS`)
- Compression (via `OTEL_EXPORTER_OTLP_COMPRESSION`)
- Timeout settings (via `OTEL_EXPORTER_OTLP_TIMEOUT`)

### Handle Exporter

A simple exporter that writes spans to a file handle (like stdout or stderr):

```haskell
-- Export spans to stdout
stdoutExporter <- stdoutExporter' defaultFormatter

-- Export spans to a file handle with custom formatter
fileHandle <- openFile "traces.log" WriteMode
fileExporter <- makeHandleExporter fileHandle defaultFormatter
```

### In-Memory Exporter

Primarily used for testing, stores spans in memory:

```haskell
-- Create in-memory exporter for testing
(processor, spansRef) <- inMemoryListExporter

-- After test, retrieve spans
spans <- readIORef spansRef
```

## Exporter Usage Patterns

### Configuration via Environment

The simplest approach is to let the SDK configure exporters via environment variables:

```haskell
main :: IO ()
main = bracket
  initializeGlobalTracerProvider  -- Uses environment to configure exporters
  shutdownTracerProvider
  $ \_ -> app
```

Common environment variables:
- `OTEL_TRACES_EXPORTER`: Comma-separated list of span exporters (default: `"otlp"`)
- `OTEL_LOGS_EXPORTER`: Comma-separated list of log exporters (default: `"otlp"`)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP exporter endpoint (default: `"http://localhost:4318"`)

### Programmatic Configuration

For more control, configure exporters programmatically:

```haskell
main :: IO ()
main = do
  -- Create exporter
  exporterConfig <- loadExporterEnvironmentVariables
  exporter <- otlpExporter exporterConfig

  -- Create processor with exporter
  processor <- batchProcessor batchTimeoutConfig exporter

  -- Create tracer provider with processor
  (_, options) <- getTracerProviderInitializationOptions
  provider <- createTracerProvider [processor] options

  -- Set as global provider and manage lifecycle
  bracket
    (setGlobalTracerProvider provider >> pure provider)
    shutdownTracerProvider
    $ \_ -> app
```

### Multiple Exporters

Multiple exporters can be used simultaneously:

```haskell
main :: IO ()
main = do
  -- Create exporters
  exporterConfig <- loadExporterEnvironmentVariables
  otlpExp <- otlpExporter exporterConfig
  consoleExp <- stdoutExporter' defaultFormatter

  -- Create processors
  otlpProc <- batchProcessor batchTimeoutConfig otlpExp
  consoleProc <- simpleProcessor (SimpleProcessorConfig consoleExp)

  -- Create provider with both processors
  (_, options) <- getTracerProviderInitializationOptions
  provider <- createTracerProvider [otlpProc, consoleProc] options

  -- Set global provider
  setGlobalTracerProvider provider
```

## Exporters and Processors

Exporters work with processors, which control how and when telemetry data is exported.

### Simple Processor

Immediately exports each span as it's completed:

```haskell
proc <- simpleProcessor (SimpleProcessorConfig exporter)
```

Pros: Low latency, immediate visibility
Cons: Less efficient, more network calls

### Batch Processor

Batches spans for more efficient export:

```haskell
proc <- batchProcessor batchTimeoutConfig exporter
```

Configuration options:
- `maxQueueSize`: Maximum spans in the buffer (default: 1024)
- `scheduledDelayMillis`: Batch flush interval in ms (default: 5000)
- `exportTimeoutMillis`: Export timeout in ms (default: 30000)
- `maxExportBatchSize`: Maximum batch size (default: 512)

Pros: More efficient, fewer network calls
Cons: Slight delay before spans are exported

## Creating Custom Exporters

To integrate with backends not supported out-of-the-box, you can create custom exporters.

### Custom Span Exporter

Basic pattern for implementing a span exporter:

```haskell
-- | A custom span exporter for ExampleBackend
createExampleExporter :: ExampleConfig -> IO SpanExporter
createExampleExporter config = do
  -- Initialize any resources (client, connection, etc.)
  client <- createExampleClient config

  -- Return the exporter
  pure $ SpanExporter
    { spanExporterExport = \spansByLibrary -> do
        -- For each instrumentation library and its spans
        forM_ (HashMap.toList spansByLibrary) $ \(instrumentationLib, spans) -> do
          -- Convert spans to the backend format
          let backendSpans = Vector.map convertToBackendFormat spans

          -- Send to backend with error handling
          result <- try $ sendToBackend client backendSpans
          case result of
            Right _ -> pure Success
            Left err -> do
              -- Log error
              putStrLn $ "Export error: " ++ show (err :: SomeException)
              pure $ Failure (Just err)
        pure Success

    , spanExporterShutdown = do
        -- Close connections, free resources
        closeExampleClient client
    }

-- Helper to convert spans to backend format
convertToBackendFormat :: ImmutableSpan -> BackendSpan
convertToBackendFormat span = BackendSpan
  { bsTraceId = spanTraceId span
  , bsSpanId = spanSpanId span
  , bsParentId = spanParentSpanId span
  , bsName = spanName span
  , bsStartTime = spanStartTime span
  , bsEndTime = spanEndTime span
  , bsAttributes = convertAttributes (spanAttributes span)
  , bsEvents = convertEvents (spanEvents span)
  , bsLinks = convertLinks (spanLinks span)
  , bsStatus = convertStatus (spanStatus span)
  }
```

### Custom Log Record Exporter

Similar pattern for log exporters:

```haskell
-- | A custom log record exporter for ExampleBackend
createExampleLogExporter :: ExampleConfig -> IO LogRecordExporter
createExampleLogExporter config = do
  -- Initialize client
  client <- createExampleClient config

  -- Create exporter arguments
  let args = LogRecordExporterArguments
        { logRecordExporterArgumentsExport = \logRecords -> do
            -- Convert log records to backend format
            let backendLogs = Vector.map convertToBackendLogFormat logRecords

            -- Send to backend with error handling
            result <- try $ sendLogsToBackend client backendLogs
            case result of
              Right _ -> pure Success
              Left err -> pure $ Failure (Just err)

        , logRecordExporterArgumentsForceFlush = do
            -- Force any buffered logs to be sent
            flushExampleClient client

        , logRecordExporterArgumentsShutdown = do
            -- Close connections, free resources
            closeExampleClient client
        }

  -- Create the thread-safe exporter
  mkLogRecordExporter args
```

### Best Practices

When implementing custom exporters:

1. **Error Handling**: Always catch exceptions and return appropriate `ExportResult` values
   ```haskell
   result <- try $ sendToBackend client data
   case result of
     Right _ -> pure Success
     Left err -> pure $ Failure (Just err)
   ```

2. **Resource Management**: Properly initialize and clean up resources
   ```haskell
   -- Acquire resources in constructor
   client <- createClient

   -- Release in shutdown
   spanExporterShutdown = closeClient client
   ```

3. **Concurrency**: Consider thread-safety for shared resources
   ```haskell
   -- Use MVars or other concurrency primitives as needed
   clientVar <- newMVar client

   spanExporterExport = \spans -> do
     withMVar clientVar $ \client -> sendToBackend client spans
   ```

4. **Timeout Handling**: Implement timeouts for backend operations
   ```haskell
   result <- timeout (30 * 1000000) $ sendToBackend client spans
   case result of
     Just success -> pure Success
     Nothing -> pure $ Failure (Just timeoutException)
   ```

5. **Serialization Performance**: Optimize conversions between OpenTelemetry and backend formats
   ```haskell
   -- Consider using Builder pattern for efficient serialization
   convertToBackendFormat span =
     runBuilder $ buildBackendSpan span
   ```

6. **Batching**: If the backend supports it, batch multiple spans in a single request
   ```haskell
   -- Send all spans in one request if possible
   let allSpans = Vector.concat $ HashMap.elems spansByLibrary
   sendBatchToBackend client allSpans
   ```

## Testing Exporter Implementations

To test custom exporters:

```haskell
-- | Test helper to create a test span
createTestSpan :: IO ImmutableSpan

-- | Test the exporter
testExporter :: IO ()
testExporter = do
  -- Create test span
  span <- createTestSpan

  -- Create exporter
  exporter <- createExampleExporter testConfig

  -- Export the span
  result <- spanExporterExport exporter $
    HashMap.singleton emptyInstrumentationLibrary (Vector.singleton span)

  -- Verify result
  result `shouldBe` Success

  -- Verify the span was received by the backend
  -- (requires backend-specific verification)

  -- Shutdown exporter
  spanExporterShutdown exporter
```

The In-Memory exporter provides a good reference for testing:

```haskell
-- Create in-memory exporter
(processor, spansRef) <- inMemoryListExporter

-- Use processor in a tracer provider
let tracer = makeTracer tracerProvider $(detectInstrumentationLibrary) tracerOptions

-- Create spans using the tracer
-- ...

-- Check exported spans
spans <- readIORef spansRef
spanNames <- mapM (pure . spanName) spans
spanNames `shouldContain` ["test-span"]
```

---

By following these patterns, you can integrate the Haskell OpenTelemetry library with any telemetry backend, even if it's not supported out-of-the-box.
