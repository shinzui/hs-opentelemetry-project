# OpenTelemetry with Effectful Guide

This guide demonstrates how to integrate OpenTelemetry tracing with the Effectful library for Haskell.

## Understanding MonadTracer

The `MonadTracer` typeclass is defined in OpenTelemetry as:

```haskell
class (Monad m) => MonadTracer m where
  getTracer :: m Tracer
```

It provides access to a `Tracer` within a monadic context, allowing the `inSpan` family of functions to work without explicitly passing a `Tracer` argument.

## Implementing MonadTracer for Effectful with Reader

The simplest approach to integrate OpenTelemetry with Effectful is to use the built-in `Reader` effect:

```haskell
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}

module App.Telemetry where

import Effectful
import Effectful.Reader.Static
import qualified OpenTelemetry.Trace.Core as OTel
import qualified OpenTelemetry.Trace.Monad as OTel

-- Define your application environment
data AppEnv = AppEnv
  { appTracer :: OTel.Tracer
  -- other environment fields
  }

-- Create MonadTracer instance using the Reader effect
instance (Reader AppEnv :> es) => OTel.MonadTracer (Eff es) where
  getTracer = appTracer <$> ask
```

### Using in Your Application

```haskell
{-# LANGUAGE BlockArguments #-}

module Main where

import Effectful
import Effectful.Reader.Static
import App.Telemetry
import OpenTelemetry.Trace.Core (makeTracer, tracerOptions, defaultSpanArguments)
import OpenTelemetry.Trace.Monad (inSpan)
import OpenTelemetry.Trace.Core (getGlobalTracerProvider, makeTracer, detectInstrumentationLibrary, tracerOptions)

-- Your business logic
processRequest :: (Reader AppEnv :> es, IOE :> es) => Request -> Eff es Response
processRequest req = 
  inSpan "process-request" defaultSpanArguments do
    -- Your request processing logic
    liftIO $ putStrLn "Processing request"
    pure (Response 200)

main :: IO ()
main = runEff do
  -- Initialize OpenTelemetry
  tp <- liftIO getGlobalTracerProvider
  let tracer = makeTracer tp $(detectInstrumentationLibrary) tracerOptions
  
  -- Create environment with tracer
  let env = AppEnv 
        { appTracer = tracer
        -- other fields
        }
  
  -- Run with the reader effect
  runReader env do
    inSpan "main-operation" defaultSpanArguments do
      -- Application code
      resp <- processRequest (Request "/api/data")
      liftIO $ print resp
```

## Alternative: Dedicated Tracer Effect

If you prefer a dedicated effect for telemetry, you can use Effectful's Reader effect internally:

```haskell
module Effectful.Tracer where

import Effectful
import Effectful.Dispatch.Static
import qualified OpenTelemetry.Trace.Core as OTel
import qualified OpenTelemetry.Trace.Monad as OTel

-- Define the Tracer effect with static dispatch for better performance
data Tracer :: Effect

type instance DispatchOf Tracer = Static WithSideEffects

newtype instance StaticRep Tracer = TracerRep OTel.Tracer

-- Public API
getTracer :: (Tracer :> es) => Eff es OTel.Tracer
getTracer = do
  TracerRep tracer <- getStaticRep
  pure tracer

-- Handler
runTracer :: OTel.Tracer -> Eff (Tracer : es) a -> Eff es a
runTracer tracer = evalStaticRep (TracerRep tracer)

-- Create MonadTracer instance
instance (Tracer :> es) => OTel.MonadTracer (Eff es) where
  getTracer = Effectful.Tracer.getTracer
```

## Working with Multiple Tracers

If your application needs different tracers for different components:

```haskell
-- In your app environment
data AppEnv = AppEnv
  { appWebTracer :: OTel.Tracer
  , appDatabaseTracer :: OTel.Tracer
  , appBackgroundTracer :: OTel.Tracer
  -- other fields
  }

-- Use the appropriate tracer for the context
withWebTracer :: (Reader AppEnv :> es) => Eff es a -> Eff es a
withWebTracer action = do
  env <- ask
  locally (\e -> e { appTracer = appWebTracer e }) action

withDatabaseTracer :: (Reader AppEnv :> es) => Eff es a -> Eff es a
withDatabaseTracer action = do
  env <- ask
  locally (\e -> e { appTracer = appDatabaseTracer e }) action
```

## Best Practices

1. **Keep it Simple**: The Reader approach is usually simpler and integrates well with existing Effectful codebases.

2. **Resource Management**: Use Effectful's resource management:

```haskell
withTracerProvider :: (IOE :> es) => (OTel.TracerProvider -> Eff es a) -> Eff es a
withTracerProvider action = bracket
  (liftIO OTel.initializeGlobalTracerProvider)
  (liftIO . OTel.shutdownTracerProvider)
  action
```

3. **Composition**: When using the Reader pattern, your environment can easily contain other necessary components:

```haskell
data AppEnv = AppEnv
  { appTracer :: OTel.Tracer
  , appLogger :: Logger
  , appConfig :: Config
  , appDatabase :: DatabaseConnection
  }
```

4. **Performance**: Static effects generally have better performance than dynamic ones. If you create a dedicated effect, consider using static dispatch.

5. **Testing**: Mock the environment in tests:

```haskell
runMockTelemetry :: Eff (Reader AppEnv : es) a -> Eff es a
runMockTelemetry = runReader mockEnv
  where
    mockEnv = AppEnv
      { appTracer = mockTracer
      -- other mocked components
      }
```

The Reader-based approach is generally simpler, more idiomatic, and better integrated with the rest of your application environment. It's particularly well-suited when your application already uses a Reader effect for configuration, logging, and other cross-cutting concerns.
