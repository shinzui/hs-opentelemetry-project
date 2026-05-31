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

A `Sampler` in OpenTelemetry Haskell is an algebraic data type (ADT). The built-in
strategies are constructors, and `CustomSampler` is the escape hatch you use to
define your own behavior:

```haskell
data Sampler
  = AlwaysOnSampler
  -- ^ Always returns RecordAndSample
  | AlwaysOffSampler
  -- ^ Always returns Drop
  | TraceIdRatioSampler !Double !Word64 !Attribute
  -- ^ Samples a fraction of trace IDs
  | ParentBasedSampler !ParentBasedOptions
  -- ^ Respects the parent span's sampling decision
  | AlwaysRecordSampler !Sampler
  -- ^ Decorator that upgrades Drop -> RecordOnly for a wrapped sampler
  | CustomSampler !T.Text !(Context -> TraceId -> T.Text -> SpanArguments -> InstrumentationLibrary -> IO SamplingDecision)
  -- ^ A user-defined sampler: a description plus a sampling function

data SamplingResult
  = Drop
  -- ^ Drop the span entirely (don't record or export)
  | RecordOnly
  -- ^ Record the span but don't export it
  | RecordAndSample
  -- ^ Include the span in the trace and sample it (export it)
  deriving (Show, Eq)

data SamplingDecision = SamplingDecision
  { samplingOutcome :: !SamplingResult
  -- ^ The sampling result: Drop, RecordOnly, or RecordAndSample
  , samplingAttributes :: !AttributeMap
  -- ^ Attributes to add to the span if it is recorded
  , samplingTraceState :: !TraceState
  -- ^ The TraceState to use for the new span
  }
```

You almost always construct custom samplers with `CustomSampler`, which pairs a
description string with a sampling function. That function takes:

1. A `Context` - Contains the parent span context (if any)
2. A `TraceId` - The trace ID for the current span
3. A `Text` name - The name of the span being created
4. `SpanArguments` - Contains additional span attributes and options
5. An `InstrumentationLibrary` - The instrumentation scope of the tracer creating
   the span (required by the spec; `InstrumentationScope` is a type alias for it)

And returns a `SamplingDecision`, which bundles three things:

1. `samplingOutcome` - One of `Drop`, `RecordOnly`, or `RecordAndSample`
2. `samplingAttributes` - An `AttributeMap` of attributes to add to the span if recorded
3. `samplingTraceState` - The `TraceState` to use for the new span

To run a sampler and read its description, use the top-level functions
`shouldSample` and `getDescription` (these are no longer record fields):

```haskell
shouldSample   :: Sampler -> Context -> TraceId -> T.Text -> SpanArguments -> InstrumentationLibrary -> IO SamplingDecision
getDescription :: Sampler -> T.Text
```

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
  CustomSampler "NameBasedSampler" $ \ctx _ name _ _scope -> do
    mspanCtxt <- sequence (getSpanContext <$> lookupSpan ctx)
    let outcome = if predicate name then RecordAndSample else Drop
        ts = maybe TraceState.empty traceState mspanCtxt
    pure (SamplingDecision outcome mempty ts)

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
import qualified Data.HashMap.Strict as H
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
  CustomSampler "AttributeBasedSampler" $ \ctx _ _ spanArgs _scope -> do
    mspanCtxt <- sequence (getSpanContext <$> lookupSpan ctx)
    let outcome = if predicate spanArgs then RecordAndSample else Drop
        ts = maybe TraceState.empty traceState mspanCtxt
    pure (SamplingDecision outcome mempty ts)

-- Note: 'attributes' on 'SpanArguments' is an 'AttributeMap'
-- (a @HashMap Text Attribute@), so we look up keys with 'H.lookup'.

-- Example: Sample spans with an "http.status_code" attribute >= 400 (errors)
errorSampler :: Sampler
errorSampler = attributeBasedSampler $ \spanArgs ->
  case H.lookup "http.status_code" (attributes spanArgs) of
    Just (AttributeValue (IntAttribute code)) -> code >= 400
    _ -> False

-- Example: Sample spans with a specific user ID
userSampler :: T.Text -> Sampler
userSampler userId = attributeBasedSampler $ \spanArgs ->
  case H.lookup "user.id" (attributes spanArgs) of
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
  CustomSampler "TimeWindowSampler" $ \ctx _ _ _ _scope -> do
    mspanCtxt <- sequence (getSpanContext <$> lookupSpan ctx)
    currentTime <- getCurrentTime
    let outcome = if isInWindow currentTime then RecordAndSample else Drop
        ts = maybe TraceState.empty traceState mspanCtxt
    pure (SamplingDecision outcome mempty ts)

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
  CustomSampler ("OrSampler{" <> getDescription s1 <> "," <> getDescription s2 <> "}") $
    \ctx tid name args scope -> do
      d1 <- shouldSample s1 ctx tid name args scope
      case samplingOutcome d1 of
        RecordAndSample -> pure d1
        _ -> shouldSample s2 ctx tid name args scope

-- | A sampler that combines two samplers with AND logic
andSampler :: Sampler -> Sampler -> Sampler
andSampler s1 s2 =
  CustomSampler ("AndSampler{" <> getDescription s1 <> "," <> getDescription s2 <> "}") $
    \ctx tid name args scope -> do
      d1 <- shouldSample s1 ctx tid name args scope
      case samplingOutcome d1 of
        RecordAndSample -> do
          d2 <- shouldSample s2 ctx tid name args scope
          -- Merge attributes from both samplers; the left map wins on key clashes.
          pure d2 {samplingAttributes = samplingAttributes d1 <> samplingAttributes d2}
        _ -> pure d1
```

Because `getDescription` and `shouldSample` are now top-level functions that work
on any `Sampler`, these combinators delegate to the wrapped samplers directly. If
you need to ensure that dropped spans still reach processors (for example, a
span-to-metrics processor), wrap any sampler with `alwaysRecord`, which upgrades a
`Drop` outcome to `RecordOnly`:

```haskell
recordingErrorSampler :: Sampler
recordingErrorSampler = alwaysRecord errorSampler
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
                      case H.lookup "priority" (attributes args) of
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

4. **Debugging**: Add informative span attributes when sampled (via the `samplingAttributes` field of the returned `SamplingDecision`) to aid in later analysis.

5. **Testing**: Write tests for your custom samplers to ensure they behave as expected.

## Conclusion

Custom samplers give you precise control over which spans are collected and exported in your OpenTelemetry-instrumented Haskell applications. By creating samplers tailored to your specific needs, you can optimize the balance between observability and performance.

For more information, refer to:
- [OpenTelemetry API Reference](https://www.stackage.org/haddock/lts/hs-opentelemetry-api/OpenTelemetry-Trace-Sampler.html)
- [OpenTelemetry Specification - Sampling](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/sdk.md#sampling)
