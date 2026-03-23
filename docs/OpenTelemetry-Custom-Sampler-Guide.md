# Writing a Custom OpenTelemetry Sampler

This guide explains how to create a custom sampler for the Haskell OpenTelemetry library. Samplers allow you to control which spans are exported, helping you manage the volume of telemetry data.

## Introduction to Sampling

Sampling is a technique for selecting a representative subset of traces to collect and export, rather than capturing all traces, which can be expensive in high-throughput systems. The Haskell OpenTelemetry library provides several built-in samplers:

- `alwaysOn`: Samples every span
- `alwaysOff`: Samples no spans
- `traceIdRatioBased`: Samples a configurable percentage of spans based on trace ID
- `parentBased`: A composite sampler that respects the sampling decision of the parent span

This guide will show you how to create your own custom sampler to implement more complex sampling strategies.

## Understanding the Sampler Type

A `Sampler` in OpenTelemetry Haskell is defined as:

```haskell
data Sampler = Sampler
  { getDescription :: T.Text
  -- ^ Returns the sampler name or short description
  , shouldSample :: Context -> TraceId -> T.Text -> SpanArguments -> IO (SamplingResult, AttributeMap, TraceState)
  -- ^ Makes a sampling decision
  }

data SamplingResult
  = Drop
  -- ^ Drop the span entirely (don't record or export)
  | RecordOnly
  -- ^ Record the span but don't export it
  | RecordAndSample
  -- ^ Include the span in the trace and sample it (export it)
  deriving (Show, Eq)
```

The `shouldSample` function takes:
1. A `Context` - Contains the parent span context (if any)
2. A `TraceId` - The trace ID for the current span
3. A `Text` name - The name of the span being created
4. `SpanArguments` - Contains additional span attributes and options

And returns:
1. A `SamplingResult` - One of `Drop`, `RecordOnly`, or `RecordAndSample`
2. An `AttributeMap` of attributes to add to the span if sampled
3. The `TraceState` to use for the new span

## Creating a Custom Sampler

Let's implement a few examples of custom samplers:

### Example 1: Sample by Span Name

This sampler will only collect spans with specific names:

```haskell
import qualified Data.Text as T
import OpenTelemetry.Context
import OpenTelemetry.Internal.Trace.Types
import OpenTelemetry.Trace.Id
import OpenTelemetry.Trace.Sampler
import OpenTelemetry.Trace.TraceState as TraceState

-- | A sampler that only samples spans with names matching a predicate
nameBasedSampler :: (T.Text -> Bool) -> Sampler
nameBasedSampler predicate =
  Sampler
    { getDescription = "NameBasedSampler"
    , shouldSample = \ctx _ name _ -> do
        mspanCtxt <- sequence (getSpanContext <$> lookupSpan ctx)
        if predicate name
          then pure (RecordAndSample, [], maybe TraceState.empty traceState mspanCtxt)
          else pure (Drop, [], maybe TraceState.empty traceState mspanCtxt)
    }

-- Usage examples:
-- Sample spans with names containing "http"
httpSampler :: Sampler
httpSampler = nameBasedSampler (T.isInfixOf "http")

-- Sample spans with names starting with "database."
databaseSampler :: Sampler
databaseSampler = nameBasedSampler (T.isPrefixOf "database.")
```

### Example 2: Sample Based on Attributes

This sampler makes decisions based on span attributes:

```haskell
import qualified Data.Text as T
import OpenTelemetry.Attributes
import OpenTelemetry.Context
import OpenTelemetry.Internal.Trace.Types
import OpenTelemetry.Trace.Id
import OpenTelemetry.Trace.Sampler
import OpenTelemetry.Trace.TraceState as TraceState

-- | A sampler that inspects span attributes to make sampling decisions
attributeBasedSampler :: (SpanArguments -> Bool) -> Sampler
attributeBasedSampler predicate =
  Sampler
    { getDescription = "AttributeBasedSampler"
    , shouldSample = \ctx _ _ spanArgs -> do
        mspanCtxt <- sequence (getSpanContext <$> lookupSpan ctx)
        if predicate spanArgs
          then pure (RecordAndSample, [], maybe TraceState.empty traceState mspanCtxt)
          else pure (Drop, [], maybe TraceState.empty traceState mspanCtxt)
    }

-- Example: Sample spans with an "http.status_code" attribute >= 400 (errors)
errorSampler :: Sampler
errorSampler = attributeBasedSampler $ \spanArgs ->
  case lookupAttribute (attributes spanArgs) "http.status_code" of
    Just (AttributeValue (IntAttribute code)) -> code >= 400
    _ -> False

-- Example: Sample spans with a specific user ID
userSampler :: T.Text -> Sampler
userSampler userId = attributeBasedSampler $ \spanArgs ->
  case lookupAttribute (attributes spanArgs) "user.id" of
    Just (AttributeValue (TextAttribute uid)) -> uid == userId
    _ -> False
```

### Example 3: Time-Based Sampling

This sampler changes sampling behavior based on time:

```haskell
import qualified Data.Text as T
import Data.Time.Clock
import OpenTelemetry.Context
import OpenTelemetry.Internal.Trace.Types
import OpenTelemetry.Trace.Id
import OpenTelemetry.Trace.Sampler
import OpenTelemetry.Trace.TraceState as TraceState

-- | A sampler that makes time-based sampling decisions
timeWindowSampler :: (UTCTime -> Bool) -> Sampler
timeWindowSampler isInWindow =
  Sampler
    { getDescription = "TimeWindowSampler"
    , shouldSample = \ctx _ _ _ -> do
        mspanCtxt <- sequence (getSpanContext <$> lookupSpan ctx)
        currentTime <- getCurrentTime
        if isInWindow currentTime
          then pure (RecordAndSample, [], maybe TraceState.empty traceState mspanCtxt)
          else pure (Drop, [], maybe TraceState.empty traceState mspanCtxt)
    }

-- Example: Sample during business hours
businessHoursSampler :: Sampler
businessHoursSampler = timeWindowSampler $ \time ->
  let hour = todHour $ timeToTimeOfDay $ utctDayTime time
  in hour >= 9 && hour < 17
```

### Example 4: Combining Custom Samplers

You can combine multiple samplers using the following pattern:

```haskell
import qualified Data.Text as T
import OpenTelemetry.Context
import OpenTelemetry.Internal.Trace.Types
import OpenTelemetry.Trace.Id
import OpenTelemetry.Trace.Sampler
import OpenTelemetry.Trace.TraceState as TraceState

-- | A sampler that combines two samplers with OR logic
orSampler :: Sampler -> Sampler -> Sampler
orSampler s1 s2 =
  Sampler
    { getDescription = "OrSampler{" <> getDescription s1 <> "," <> getDescription s2 <> "}"
    , shouldSample = \ctx tid name args -> do
        (result1, attrs1, ts1) <- shouldSample s1 ctx tid name args
        case result1 of
          RecordAndSample -> pure (RecordAndSample, attrs1, ts1)
          Drop -> shouldSample s2 ctx tid name args
    }

-- | A sampler that combines two samplers with AND logic
andSampler :: Sampler -> Sampler -> Sampler
andSampler s1 s2 =
  Sampler
    { getDescription = "AndSampler{" <> getDescription s1 <> "," <> getDescription s2 <> "}"
    , shouldSample = \ctx tid name args -> do
        (result1, attrs1, ts1) <- shouldSample s1 ctx tid name args
        case result1 of
          Drop -> pure (Drop, attrs1, ts1)
          RecordAndSample -> do
            (result2, attrs2, _) <- shouldSample s2 ctx tid name args
            pure (result2, attrs1 ++ attrs2, ts1)
    }
```

## Using Your Custom Sampler

To use your custom sampler with the OpenTelemetry SDK, you need to:

1. Create an instance of your sampler
2. Pass it to your `TracerProvider` when initializing it

For example:

```haskell
import OpenTelemetry.Trace (createTracerProvider)
import OpenTelemetry.Trace.Core (emptyTracerProviderOptions, TracerProviderOptions(..))

main :: IO ()
main = do
  -- Create a custom sampler
  let mySampler = orSampler
                    (nameBasedSampler (T.isPrefixOf "critical."))
                    (attributeBasedSampler (\args ->
                      case lookupAttribute (attributes args) "priority" of
                        Just (AttributeValue (TextAttribute p)) -> p == "high"
                        _ -> False))

  -- Use the sampler when creating a tracer provider
  let options = emptyTracerProviderOptions
                  { tracerProviderOptionsSampler = mySampler }
  tracerProvider <- createTracerProvider [] options

  -- Use the tracer provider...
```

## Best Practices for Custom Samplers

1. **Performance Considerations**: Sampling decisions happen on the hot path of your application. Keep your samplers efficient.

2. **Context Propagation**: Respect parent sampling decisions when appropriate.

3. **Sampling Rate Consistency**: When creating ratio-based samplers, ensure the sampling algorithm is consistent so related spans are sampled together.

4. **Debugging**: Add informative span attributes when sampled (using the second return value of `shouldSample`) to aid in later analysis.

5. **Testing**: Write tests for your custom samplers to ensure they behave as expected.

## Conclusion

Custom samplers give you precise control over which spans are collected and exported in your OpenTelemetry-instrumented Haskell applications. By creating samplers tailored to your specific needs, you can optimize the balance between observability and performance.

For more information, refer to:
- [OpenTelemetry API Reference](https://www.stackage.org/haddock/lts/hs-opentelemetry-api/OpenTelemetry-Trace-Sampler.html)
- [OpenTelemetry Specification - Sampling](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/sdk.md#sampling)
