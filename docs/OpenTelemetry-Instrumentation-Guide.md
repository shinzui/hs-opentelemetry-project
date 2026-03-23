# OpenTelemetry Instrumentation Guide

This guide explains how to create instrumentation for Haskell libraries and how to use the OpenTelemetry API's instrumentation helpers.

## Understanding Library Instrumentation

In OpenTelemetry, there are two key concepts related to instrumentation:

1. **Instrumented Library**: The library or application that you want to observe with telemetry data.

2. **Instrumentation Library**: The library that provides the OpenTelemetry integration for the instrumented library.

Sometimes, these are the same library (when a library has built-in OpenTelemetry support), but often you'll create a separate instrumentation library for an existing codebase.

## Using `detectInstrumentationLibrary`

One of the key functions for instrumenting libraries is `detectInstrumentationLibrary`, which automatically determines your instrumentation library information based on the Haskell package name and version.

### What is `detectInstrumentationLibrary`?

`detectInstrumentationLibrary` is a Template Haskell function that:

1. Automatically extracts the current package name and version at compile time
2. Creates an `InstrumentationLibrary` value with this information
3. Provides proper identification in telemetry data for your library

### How to Use It

```haskell
import OpenTelemetry.Trace.Core

-- Create a tracer for your instrumentation library
myTracer :: IO Tracer
myTracer = do
  tp <- getGlobalTracerProvider
  pure $ makeTracer tp $(detectInstrumentationLibrary) tracerOptions
```

This approach ensures that:
- The tracer is properly identified with your library's name and version
- Spans created by this tracer will be associated with your library
- Backend systems can identify which library generated each span

### The `InstrumentationLibrary` Type

The `InstrumentationLibrary` type contains:

```haskell
data InstrumentationLibrary = InstrumentationLibrary
  { libraryName :: Text       -- The name of the instrumentation library
  , libraryVersion :: Text    -- The version of the instrumented library
  , librarySchemaUrl :: Text  -- URL pointing to the schema for this instrumentation 
  , libraryAttributes :: Attributes -- Additional attributes for this library
  }
```

## Creating an Instrumentation Library

Follow these steps to create an effective instrumentation library:

### 1. Project Structure

Follow OpenTelemetry's naming convention for your package:

```
hs-opentelemetry-instrumentation-{target-library}
```

For example:
- `hs-opentelemetry-instrumentation-wai`
- `hs-opentelemetry-instrumentation-http-client`

### 2. Define the Instrumentation API

Create a clear API that will be easy for users to integrate. Common patterns include:

1. **Middleware Pattern**: For web frameworks and middleware stacks
   ```haskell
   otelMiddleware :: Middleware
   otelMiddleware app req respond = do
     -- Create a span for each request
     -- ...
   ```

2. **Wrapper Pattern**: For functions and clients
   ```haskell
   withTracedConnection :: Connection -> (Connection -> IO a) -> IO a
   ```

3. **Instrumented Client Pattern**: For database clients and HTTP clients
   ```haskell
   createInstrumentedClient :: ClientConfig -> IO InstrumentedClient
   ```

### 3. Implementing the Instrumentation

A typical instrumentation implementation involves:

```haskell
module OpenTelemetry.Instrumentation.MyLibrary where

import OpenTelemetry.Trace.Core
import OpenTelemetry.Context.ThreadLocal

-- Create a tracer provider and tracer
myLibraryTracerProvider :: IO Tracer
myLibraryTracerProvider = do
  tp <- getGlobalTracerProvider
  pure $ makeTracer tp $(detectInstrumentationLibrary) tracerOptions

-- Create a function that instruments the target library
instrumentOperation :: Operation -> IO Result
instrumentOperation op = do
  tracer <- myLibraryTracerProvider
  inSpan tracer "my.library.operation" defaultSpanArguments{
    kind = Internal,
    attributes = [
      ("my.library.operation.name", toAttribute $ operationName op),
      ("my.library.operation.id", toAttribute $ operationId op)
    ]
  } $ do
    -- Perform the operation
    result <- performOperation op
    
    -- Add more attributes based on the result
    addAttribute s "my.library.operation.status" (resultStatus result)
    
    pure result
```

### 4. Adding Semantic Conventions

Follow the OpenTelemetry semantic conventions for naming spans and attributes:

- HTTP client spans should be named after the HTTP method: `GET`, `POST`, etc.
- Database spans should include the operation type: `SELECT`, `INSERT`, etc.
- Use standard attribute names like `http.method`, `db.system`, etc.

## Complete Example: HTTP Client Instrumentation

Here's a complete example of instrumenting an HTTP client:

```haskell
module OpenTelemetry.Instrumentation.HttpClient where

import Control.Monad.IO.Class
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Network.HTTP.Client
import Network.HTTP.Types
import OpenTelemetry.Context
import OpenTelemetry.Trace.Core

-- Configuration for the instrumentation
data HttpClientConfig = HttpClientConfig
  { recordRequestHeaders :: [HeaderName]  -- Headers to record as span attributes
  , recordResponseHeaders :: [HeaderName] -- Headers to record as span attributes
  }

defaultHttpClientConfig :: HttpClientConfig
defaultHttpClientConfig = HttpClientConfig [] []

-- Create a tracer for HTTP client operations
httpClientTracer :: IO Tracer
httpClientTracer = do
  tp <- getGlobalTracerProvider
  pure $ makeTracer tp $(detectInstrumentationLibrary) tracerOptions

-- Create an instrumented HTTP manager
createInstrumentedManager :: HttpClientConfig -> IO Manager
createInstrumentedManager config = do
  tracer <- httpClientTracer
  newManager $ defaultManagerSettings
    { managerModifyRequest = \req -> instrumentRequest tracer config req
    }

-- Instrument an individual request
instrumentRequest :: Tracer -> HttpClientConfig -> Request -> IO Request
instrumentRequest tracer config req = do
  -- Get the current context
  ctx <- getContext
  
  -- Create a span for the HTTP request
  inSpan tracer (T.decodeUtf8 $ method req) defaultSpanArguments
    { kind = Client
    , attributes =
        [ ("http.method", toAttribute $ T.decodeUtf8 $ method req)
        , ("http.url", toAttribute $ T.decodeUtf8 $ host req)
        , ("http.scheme", toAttribute $ if secure req then "https" else "http")
        ]
    } $ \span -> do
      -- Add request headers to propagate context
      hdrs <- inject (getTracerProviderPropagators $ tracerProvider tracer) ctx $ requestHeaders req
      
      -- Return the modified request with context propagation
      pure $ req { requestHeaders = hdrs }
```

## Best Practices for Library Instrumentation

1. **Use `detectInstrumentationLibrary`** instead of hardcoding library names and versions.

2. **Follow semantic conventions** for span names, attributes, and event names.

3. **Propagate context** between services using appropriate propagators.

4. **Provide configuration options** to control the level of instrumentation.

5. **Add useful attributes** that help with debugging and monitoring.

6. **Handle errors properly** by recording exceptions and setting appropriate span status.

7. **Keep instrumentation lightweight** to minimize performance impact.

8. **Test your instrumentation** to ensure it works correctly in different scenarios.

## Conclusion

Creating instrumentation for Haskell libraries using OpenTelemetry provides valuable insights into your application's behavior. By following the patterns and best practices outlined in this guide, you can create effective instrumentation that integrates well with the broader OpenTelemetry ecosystem.

Remember that good instrumentation is:
- Unobtrusive - it shouldn't require major changes to application code
- Informative - it should capture relevant details about operations
- Configurable - users should be able to control what gets recorded
- Standards-compliant - it should follow OpenTelemetry semantic conventions
