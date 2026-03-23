# ImmutableSpan Guide

## Overview

`ImmutableSpan` is a core data type in the OpenTelemetry Haskell implementation that represents a frozen, read-only snapshot of a span's data. It serves as the primary data structure used by span processors and exporters to safely access span information without worrying about concurrent modifications.

## Purpose and Design

In OpenTelemetry's architecture, spans go through different lifecycle phases:

1. **Active Phase**: The span is being actively modified (adding events, attributes, etc.)
2. **Ended Phase**: The span has ended but hasn't been exported yet
3. **Export Phase**: The span data is being sent to backend systems

`ImmutableSpan` represents the span data during the ended and export phases. When a span ends, its mutable state is frozen into an `ImmutableSpan` structure that can be safely passed to multiple processors and exporters.

## Data Structure

The `ImmutableSpan` type contains all the information about a span:

```haskell
data ImmutableSpan = ImmutableSpan
  { spanName :: Text
  -- ^ The name of the span, identifying its role
  
  , spanParent :: Maybe Span
  -- ^ Reference to the parent span, if any
  
  , spanContext :: SpanContext
  -- ^ The immutable context containing trace ID, span ID, and flags
  
  , spanKind :: SpanKind
  -- ^ The type of span: Server, Client, Producer, Consumer, or Internal
  
  , spanStart :: Timestamp
  -- ^ When the span started
  
  , spanEnd :: Maybe Timestamp
  -- ^ When the span ended (Nothing if still active)
  
  , spanAttributes :: Attributes
  -- ^ Key-value pairs of metadata
  
  , spanLinks :: AppendOnlyBoundedCollection Link
  -- ^ Links to causally related spans
  
  , spanEvents :: AppendOnlyBoundedCollection Event
  -- ^ Point-in-time occurrences within the span
  
  , spanStatus :: SpanStatus
  -- ^ The status: Unset, Error, or Ok
  
  , spanTracer :: Tracer
  -- ^ The tracer that created this span
  }
```

## Span Types in OpenTelemetry

OpenTelemetry Haskell uses a type-safe approach to represent different kinds of spans:

```haskell
data Span
  = Span (IORef ImmutableSpan)
  -- ^ A mutable span created by this process
  
  | FrozenSpan SpanContext
  -- ^ An immutable span from another process (remote span)
  
  | Dropped SpanContext
  -- ^ A span that was dropped due to sampling
```

The `ImmutableSpan` is stored inside the `IORef` for mutable spans. This allows the span to be modified during its active phase while providing a consistent snapshot when needed.

## Working with ImmutableSpan

### Converting a Span to ImmutableSpan

The `toImmutableSpan` function converts a `Span` to its immutable representation:

```haskell
toImmutableSpan :: MonadIO m => Span -> m (Either FrozenOrDropped ImmutableSpan)
```

This function returns:
- `Right ImmutableSpan` if the span is mutable (created by this process)
- `Left SpanFrozen` if the span is from another process
- `Left SpanDropped` if the span was dropped

Example usage:

```haskell
import OpenTelemetry.Trace.Core

processSpan :: Span -> IO ()
processSpan span = do
  result <- toImmutableSpan span
  case result of
    Right immutableSpan -> do
      -- Process the local span
      putStrLn $ "Processing span: " <> T.unpack (spanName immutableSpan)
      
    Left SpanFrozen -> 
      putStrLn "Cannot process frozen span from another process"
      
    Left SpanDropped -> 
      putStrLn "Span was dropped"
```

### Accessing Span Data

Once you have an `ImmutableSpan`, you can safely access all its fields:

```haskell
analyzeSpan :: ImmutableSpan -> IO ()
analyzeSpan span = do
  -- Access basic information
  putStrLn $ "Span name: " <> T.unpack (spanName span)
  putStrLn $ "Span kind: " <> show (spanKind span)
  
  -- Check duration
  case spanEnd span of
    Just endTime -> do
      let duration = endTime - spanStart span
      putStrLn $ "Duration: " <> show duration <> " nanoseconds"
    Nothing -> 
      putStrLn "Span hasn't ended yet"
  
  -- Access attributes
  let attrs = getAttributeMap (spanAttributes span)
  forM_ (HM.toList attrs) $ \(key, value) ->
    putStrLn $ T.unpack key <> ": " <> show value

  -- Check status
  case spanStatus span of
    Ok -> putStrLn "Span completed successfully"
    Error description -> putStrLn $ "Span failed: " <> T.unpack description
    Unset -> putStrLn "Span status not set"
```

## Use in Processors

Span processors receive `IORef ImmutableSpan` in their callbacks:

```haskell
data SpanProcessor = SpanProcessor
  { spanProcessorOnStart :: IORef ImmutableSpan -> Context -> IO ()
  , spanProcessorOnEnd :: IORef ImmutableSpan -> IO ()
  , spanProcessorShutdown :: IO (Async ShutdownResult)
  , spanProcessorForceFlush :: IO ()
  }
```

Example processor that logs span information:

```haskell
loggingProcessor :: SpanProcessor
loggingProcessor = SpanProcessor
  { spanProcessorOnStart = \spanRef ctx -> do
      span <- readIORef spanRef
      putStrLn $ "Span started: " <> T.unpack (spanName span)
      
  , spanProcessorOnEnd = \spanRef -> do
      span <- readIORef spanRef
      putStrLn $ "Span ended: " <> T.unpack (spanName span)
      -- Log attributes
      let attrs = getAttributeMap (spanAttributes span)
      forM_ (HM.toList attrs) $ \(key, value) ->
        putStrLn $ "  " <> T.unpack key <> ": " <> show value
        
  , spanProcessorShutdown = async $ pure ShutdownSuccess
  , spanProcessorForceFlush = pure ()
  }
```

## Use in Exporters

Exporters receive batches of `ImmutableSpan` grouped by instrumentation library:

```haskell
data SpanExporter = SpanExporter
  { spanExporterExport :: HashMap InstrumentationLibrary (Vector ImmutableSpan) -> IO ExportResult
  , spanExporterShutdown :: IO ()
  }
```

Example exporter that counts spans by kind:

```haskell
countingExporter :: SpanExporter
countingExporter spans = do
  let allSpans = concat $ V.toList <$> HM.elems spans
      kindCounts = foldr countKind mempty allSpans
      
  forM_ (HM.toList kindCounts) $ \(kind, count) ->
    putStrLn $ show kind <> ": " <> show count
    
  pure Success
  where
    countKind span acc = 
      HM.insertWith (+) (spanKind span) 1 acc
```

## Best Practices

1. **Never Modify**: `ImmutableSpan` should be treated as read-only. The `IORef` in processors is for reading only.

2. **Efficient Access**: When processing many spans, consider extracting only the fields you need rather than passing around the entire structure.

3. **Attribute Access**: Use the provided functions like `lookupAttribute` and `getAttributeMap` to safely access span attributes.

4. **Memory Considerations**: `ImmutableSpan` contains the full span data. In high-volume scenarios, consider what data you actually need to retain.

5. **Error Handling**: Always handle the `Either` result from `toImmutableSpan` appropriately, as not all spans can be converted.

## Example: Custom Span Analysis

Here's a complete example that analyzes spans for performance issues:

```haskell
{-# LANGUAGE OverloadedStrings #-}
import OpenTelemetry.Trace.Core
import qualified Data.Text as T
import qualified Data.HashMap.Strict as HM

-- Analyze spans for slow operations
analyzePerformance :: ImmutableSpan -> IO ()
analyzePerformance span = do
  case spanEnd span of
    Just endTime -> do
      let duration = endTime - spanStart span
          durationMs = fromIntegral duration / 1_000_000
          
      when (durationMs > 1000) $ do  -- Flag operations over 1 second
        putStrLn $ "SLOW OPERATION DETECTED"
        putStrLn $ "Span: " <> T.unpack (spanName span)
        putStrLn $ "Duration: " <> show durationMs <> " ms"
        
        -- Check for database operations
        case lookupAttribute (spanAttributes span) "db.statement" of
          Just (AttributeValue (TextAttribute query)) ->
            putStrLn $ "Slow query: " <> T.unpack query
          _ -> pure ()
          
        -- Check HTTP operations
        case lookupAttribute (spanAttributes span) "http.url" of
          Just (AttributeValue (TextAttribute url)) ->
            putStrLn $ "Slow HTTP request: " <> T.unpack url
          _ -> pure ()
          
    Nothing -> pure ()  -- Span hasn't ended

-- Create a processor that performs analysis
performanceAnalysisProcessor :: SpanProcessor
performanceAnalysisProcessor = SpanProcessor
  { spanProcessorOnStart = \_ _ -> pure ()
  , spanProcessorOnEnd = \spanRef -> do
      span <- readIORef spanRef
      analyzePerformance span
  , spanProcessorShutdown = async $ pure ShutdownSuccess
  , spanProcessorForceFlush = pure ()
  }
```

## Conclusion

`ImmutableSpan` is a fundamental building block for OpenTelemetry's processing pipeline in Haskell. It provides a type-safe, immutable representation of span data that can be safely shared across threads and components. Understanding how to work with `ImmutableSpan` is essential for building custom processors, exporters, and analysis tools in the OpenTelemetry Haskell ecosystem.
