# Extending Batch Processor with Filtering

> **Note**: The filtering capabilities described in this guide are not built into the
> `hs-opentelemetry-sdk` package. This guide shows patterns for implementing filtering
> as custom code in your application, using the `SpanProcessor` interface.

## Overview

The OpenTelemetry Batch Processor is responsible for batching spans before sending them to exporters. This guide explains how to extend the existing Batch Processor to support filtering, allowing you to selectively process spans based on custom criteria.

## Current Batch Processor Architecture

The Batch Processor in `hs-opentelemetry` uses the following key components:

1. **BoundedMap**: A thread-safe data structure that stores spans grouped by instrumentation library
2. **Worker Thread**: Exports batches when they reach size limits or on timeout
3. **STM (Software Transactional Memory)**: Ensures thread-safe operations

The processing flow:
1. Spans are added via `spanProcessorOnEnd`
2. They're stored in a `BoundedMap` with a maximum size
3. Batches are exported when full or after a timeout

## Filtering Strategies

There are several approaches to add filtering capabilities:

### Strategy 1: Filter in the Processor (Recommended)

Add filtering directly to the Batch Processor by modifying the `spanProcessorOnEnd` function.

```haskell
-- Add a filter type to the configuration
-- The actual BatchTimeoutConfig (from OpenTelemetry.Processor.Batch.Span):
data BatchTimeoutConfig = BatchTimeoutConfig
  { maxQueueSize :: Int          -- Default: 1024
  , scheduledDelayMillis :: Int  -- Default: 5000
  , exportTimeoutMillis :: Int   -- Default: 30000
  , maxExportBatchSize :: Int    -- Default: 512
  }

-- To add filtering, create a wrapper around SpanProcessor (see Strategy 2 below)

-- Strategy 1 would involve modifying the library source code, which is not
-- recommended. Instead, use the Filtering Processor Wrapper pattern (Strategy 2).
```

### Strategy 2: Filtering Processor Wrapper

Create a separate filtering processor that wraps any other processor:

```haskell
-- A processor that filters spans before passing to another processor
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

-- Usage example
createFilteredBatchProcessor :: SpanExporter -> IO SpanProcessor
createFilteredBatchProcessor exporter = do
  batchProc <- batchProcessor batchTimeoutConfig exporter
  let filterFn = not . isHealthCheck
  pure $ filteringProcessor filterFn batchProc
  where
    isHealthCheck span = 
      spanName span == "/health" || spanName span == "/metrics"
```

### Strategy 3: Custom Batch Processor

Create a completely custom batch processor with built-in filtering:

```haskell
data FilteredBatchConfig = FilteredBatchConfig
  { baseConfig :: BatchTimeoutConfig
  , inclusionFilter :: ImmutableSpan -> Bool
  , samplingRate :: Maybe Double  -- Optional sampling
  }

filteredBatchProcessor :: FilteredBatchConfig -> IO SpanProcessor
filteredBatchProcessor config = do
  -- Create bounded map for filtered spans
  bm <- newBoundedMap (maxQueueSize $ baseConfig config)
  
  -- Setup worker thread
  worker <- async $ forever $ do
    -- Export logic with filtering applied
    
  pure SpanProcessor
    { spanProcessorOnStart = \_ _ -> pure ()
    , spanProcessorOnEnd = \spanRef -> do
        span <- readIORef spanRef
        
        -- Apply inclusion filter
        when (inclusionFilter config span) $ do
          -- Apply sampling if configured
          shouldSample <- case samplingRate config of
            Nothing -> pure True
            Just rate -> (< rate) <$> randomRIO (0, 1)
            
          when shouldSample $ push bm span
            
    , spanProcessorShutdown = -- shutdown logic
    , spanProcessorForceFlush = -- flush logic
    }
```

## Common Filtering Patterns

### 1. Filter by Span Name

```haskell
-- Exclude health checks and metrics endpoints
excludeHealthChecks :: ImmutableSpan -> Bool
excludeHealthChecks span = 
  not $ spanName span `elem` ["/health", "/metrics", "/ping"]

-- Include only specific operations
includeOnlyAPI :: ImmutableSpan -> Bool
includeOnlyAPI span = 
  "/api/" `T.isPrefixOf` spanName span
```

### 2. Filter by Attributes

```haskell
-- Filter based on HTTP status code
excludeSuccessfulRequests :: ImmutableSpan -> Bool
excludeSuccessfulRequests span =
  case lookupAttribute (spanAttributes span) "http.status_code" of
    Just (AttributeValue (IntAttribute code)) -> code >= 400
    _ -> True  -- Include if no status code

-- Filter by custom attributes
hasCustomAttribute :: Text -> ImmutableSpan -> Bool
hasCustomAttribute key span = 
  isJust $ lookupAttribute (spanAttributes span) key
```

### 3. Filter by Duration

```haskell
-- Only include slow operations
filterSlowOperations :: Int -> ImmutableSpan -> Bool
filterSlowOperations thresholdMs span =
  case spanEnd span of
    Just endTime ->
      let duration = endTime - spanStart span
          durationMs = fromIntegral duration / 1_000_000
      in durationMs > fromIntegral thresholdMs
    Nothing -> False  -- Exclude if not ended
```

### 4. Filter by Span Kind

```haskell
-- Only export server spans
serverSpansOnly :: ImmutableSpan -> Bool
serverSpansOnly span = spanKind span == Server

-- Exclude internal spans
excludeInternalSpans :: ImmutableSpan -> Bool
excludeInternalSpans span = spanKind span /= Internal
```

### 5. Composite Filters

```haskell
-- Combine multiple filters
compositeFilter :: ImmutableSpan -> Bool
compositeFilter span = 
  all ($ span) 
    [ excludeHealthChecks
    , not . hasErrorStatus
    , hasSufficientDuration
    ]
  where
    hasErrorStatus s = case spanStatus s of
      Error _ -> True
      _ -> False
      
    hasSufficientDuration s = 
      case spanEnd s of
        Just end -> (end - spanStart s) > 1_000_000  -- > 1ms
        Nothing -> False
```

## Implementation Example

Here's a complete example extending the Batch Processor with filtering:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module OpenTelemetry.Processor.Batch.Filtered where

import OpenTelemetry.Processor.Batch
import OpenTelemetry.Trace.Core
import qualified Data.Text as T

-- Extended configuration with filtering
data FilteredBatchConfig = FilteredBatchConfig
  { batchConfig :: BatchTimeoutConfig
  , spanFilter :: ImmutableSpan -> Bool
  , filterName :: Text  -- For debugging
  }

-- Default filters
defaultFilters :: [(Text, ImmutableSpan -> Bool)]
defaultFilters = 
  [ ("no-filter", const True)
  , ("errors-only", isErrorSpan)
  , ("slow-ops", isSlowOperation 1000)
  , ("no-health", excludeHealthEndpoints)
  , ("sampling-10", const True)  -- Implement with random sampling
  ]

isErrorSpan :: ImmutableSpan -> Bool
isErrorSpan span = case spanStatus span of
  Error _ -> True
  _ -> False

isSlowOperation :: Int -> ImmutableSpan -> Bool
isSlowOperation thresholdMs span =
  case spanEnd span of
    Just endTime ->
      let durationMs = fromIntegral (endTime - spanStart span) / 1_000_000
      in durationMs > fromIntegral thresholdMs
    Nothing -> False

excludeHealthEndpoints :: ImmutableSpan -> Bool
excludeHealthEndpoints span =
  not $ any (`T.isInfixOf` spanName span) 
    ["/health", "/metrics", "/ready", "/alive"]

-- Create filtered batch processor
createFilteredBatchProcessor :: FilteredBatchConfig -> SpanExporter -> IO SpanProcessor
createFilteredBatchProcessor config exporter = do
  -- Create base processor
  baseProcessor <- batchProcessor (batchConfig config) exporter

  -- Wrap with filtering
  pure $ filteringProcessor (spanFilter config) baseProcessor

-- Helper to create processor with named filter
withNamedFilter :: Text -> BatchTimeoutConfig -> IO SpanProcessor
withNamedFilter filterName config =
  case lookup filterName defaultFilters of
    Just filterFn -> 
      createFilteredBatchProcessor $ FilteredBatchConfig config filterFn filterName
    Nothing -> 
      error $ "Unknown filter: " <> T.unpack filterName

-- Advanced: Chained filters
chainFilters :: [ImmutableSpan -> Bool] -> ImmutableSpan -> Bool
chainFilters filters span = all ($ span) filters

-- Advanced: Dynamic filter based on environment
createDynamicFilter :: IO (ImmutableSpan -> Bool)
createDynamicFilter = do
  -- Could read from environment, config file, etc.
  includeErrors <- maybe False (== "true") <$> lookupEnv "OTEL_INCLUDE_ERRORS_ONLY"
  excludeHealth <- maybe True (== "true") <$> lookupEnv "OTEL_EXCLUDE_HEALTH"
  
  pure $ \span -> 
    (not includeErrors || isErrorSpan span) &&
    (not excludeHealth || excludeHealthEndpoints span)
```

## Usage Example

```haskell
import OpenTelemetry.Trace

main :: IO ()
main = do
  -- Create a filtered batch processor
  let config = FilteredBatchConfig
        { batchConfig = batchTimeoutConfig
        , spanFilter = compositeFilter
        , filterName = "production-filter"
        }
  
  processor <- createFilteredBatchProcessor config
  
  -- Use with tracer provider
  tracerProvider <- createTracerProvider [processor] emptyTracerProviderOptions
  
  -- Your application code
  withTracer tracerProvider "my-service" $ \tracer -> do
    -- Spans matching the filter will be exported
    inSpan tracer "important-operation" defaultSpanArguments $ do
      -- This will be exported if it matches the filter
      doImportantWork
```

## Performance Considerations

1. **Filter Early**: Apply filters in `spanProcessorOnEnd` to avoid storing filtered spans
2. **Efficient Filters**: Keep filter functions fast as they run on every span
3. **Avoid Complex Lookups**: Cache attribute keys if filtering by attributes frequently
4. **Batch Size**: Adjust batch sizes based on expected filtering rates

## Testing Filters

```haskell
import Test.Hspec

spec :: Spec
spec = describe "Span Filtering" $ do
  it "filters health check endpoints" $ do
    let span = createTestSpan "/health"
    excludeHealthEndpoints span `shouldBe` False
    
  it "includes error spans" $ do
    let span = createTestSpan "operation" & setStatus (Error "failed")
    isErrorSpan span `shouldBe` True
    
  it "filters by duration" $ do
    let span = createTestSpan "slow-op" 
          & setDuration 2000  -- 2 seconds
    isSlowOperation 1000 span `shouldBe` True
```

## Best Practices

1. **Document Filters**: Clearly document what each filter does and why
2. **Monitor Impact**: Track how many spans are filtered vs. exported
3. **Configuration**: Make filters configurable via environment or config files
4. **Fail Open**: When in doubt, export the span rather than drop it
5. **Test Thoroughly**: Ensure filters don't accidentally drop important spans

## Conclusion

Extending the Batch Processor with filtering provides powerful control over which spans are exported. Whether you choose to modify the existing processor, create a wrapper, or build a custom implementation depends on your specific needs. The key is to implement filtering efficiently while maintaining the reliability of span export.
