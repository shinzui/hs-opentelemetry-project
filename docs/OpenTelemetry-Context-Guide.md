# OpenTelemetry Context: In-Depth Implementation and Usage Guide

## Introduction

OpenTelemetry Context is a crucial mechanism for propagating execution-scoped values across API boundaries and between logically associated execution units in a distributed system. This document explains the design, implementation, and proper usage of Context in Haskell applications, especially in multithreaded environments.

## Conceptual Overview

Context is one of the fundamental pillars of distributed tracing, enabling correlation of events across service boundaries. It typically contains:

- Information identifying the current span and trace
- Baggage items (arbitrary correlations as key-value pairs)
- Other cross-cutting concerns that need to be propagated

OpenTelemetry Context is designed to be a carrier that can be passed between components, services, and across thread boundaries, maintaining trace continuity throughout a distributed system.

## Implementation Details

### Core Components

The OpenTelemetry Context implementation in Haskell consists of several key components:

#### 1. Context Type

```haskell
-- From OpenTelemetry.Context.Types
newtype Context = Context V.Vault
```

The Context is implemented as a wrapper around `Data.Vault.Strict.Vault` which provides:
- Type-safe storage for heterogeneous values
- Efficient lookup by unique keys
- Thread-safety through immutability

### Understanding Vault

The `vault` package is fundamental to OpenTelemetry's Context implementation. Vault provides a type-safe, heterogeneous container with several key properties:

#### How Vault Works

```haskell
-- Simplified representation of core Vault types
data Key a        -- A unique key associated with a specific type
newtype Vault     -- A heterogeneous map from keys to values
```

Vault solves an important problem in Haskell: how to store values of different types in a single container while maintaining type safety. It achieves this through a clever combination of:

1. **Unique Key Generation**: Keys are created in the IO monad using techniques similar to `newIORef` to ensure global uniqueness.

2. **Type-Safety**: Each key is associated with a specific type at creation time. This association is enforced by the Haskell type system, making it impossible to store a value of the wrong type or retrieve a value as the wrong type.

3. **Efficient Implementation**: Internally, Vault uses a map from unique integer identifiers to boxed values, with careful handling to prevent space leaks.

#### Vault vs. Other Approaches

Compared to other approaches for heterogeneous containers in Haskell:

- **Dynamic**: `Data.Dynamic` allows arbitrary type storage but requires runtime type checking, which can fail.
- **TypeRep Map**: Using `Data.Typeable` for type-indexed maps can only store one value per type.
- **Vault**: Combines the flexibility of Dynamic with the safety of strong typing by associating types with unique keys rather than just the types themselves.

#### Performance Characteristics

- Key creation is relatively expensive (requires IO) but is typically done once at startup
- Lookups and insertions are O(log n) operations (based on internal map implementation)
- Memory overhead is minimal compared to alternatives for heterogeneous storage

In OpenTelemetry, Vault allows the Context to store various telemetry components (spans, baggage, etc.) in a type-safe manner while still permitting arbitrary extension by library users without risk of key collisions.

#### 2. Key Type

```haskell
-- From OpenTelemetry.Context.Types
data Key a = Key {keyName :: Text, key :: V.Key a}
```

Keys are used to control access to specific values within a Context. Each key:
- Has a human-readable name for debugging purposes
- Contains an internal unique identifier (`V.Key`) that ensures type safety
- Is created uniquely to prevent accidental collisions across libraries

#### 3. Thread-Local Storage

Context instances need to be associated with the current thread of execution to be useful in multithreaded environments. This is implemented in `OpenTelemetry.Context.ThreadLocal` using the `thread-utils-context` package:

```haskell
-- From OpenTelemetry.Context.ThreadLocal
type ThreadContextMap = ThreadStorageMap Context

threadContextMap :: ThreadContextMap
threadContextMap = unsafePerformIO newThreadStorageMap
{-# NOINLINE threadContextMap #-}
```

### GHC Internals: Understanding the Implementation

The thread-local storage implementation relies on GHC runtime internals to provide thread-specific context management. Here's what's happening under the hood:

#### ThreadStorageMap Implementation

The `ThreadStorageMap` from the `thread-utils-context` package:

1. Uses GHC's `StableName#` mechanism to create weak references to threads
2. Employs striping (32 sections) to reduce contention in multithreaded scenarios
3. Registers finalizers on `ThreadId` objects to automatically clean up context values when threads terminate
4. Uses weak pointers to allow garbage collection of contexts when no longer referenced

### In-Depth: thread-utils-context Package

The `thread-utils-context` package is a cornerstone of OpenTelemetry's multithreaded context management. It provides the low-level machinery needed to associate contexts with specific threads and manage their lifecycle.

#### Core Abstractions

```haskell
-- Core type
newtype ThreadStorageMap a
  -- Maps ThreadId to values of type 'a'
  -- Unlike typical maps, this handles thread lifecycle automatically
```

#### Key Features

1. **Thread-Local Storage**: Allows storing values associated with specific threads, accessible throughout a program
2. **Automatic Cleanup**: Uses GHC's garbage collection to clean up values when threads terminate
3. **Thread-Safety**: Designed for concurrent access with minimal contention
4. **Cross-Thread Access**: Enables retrieving and modifying values on other threads (with caution)

#### Detailed Implementation Mechanics

The implementation uses several advanced GHC runtime features:

##### StableName# and Weak References

```haskell
-- Conceptual representation (actual implementation is more complex)
type ThreadMap = Map StableName# (Weak (ThreadId, a))
```

1. `StableName#` provides a stable way to compare `ThreadId` values by identity, rather than by their constructor values.
2. `Weak` references prevent memory leaks by allowing the garbage collector to collect the thread and its associated data.
3. Finalizers are attached to clean up entries when threads terminate.

##### Concurrency Control

The implementation uses a striping technique with 32 separate maps to reduce lock contention:

1. Each `ThreadId` is hashed to determine which stripe it belongs to
2. Operations only lock one stripe at a time, allowing concurrent access to different stripes
3. Each stripe has its own lock, minimizing thread blocking

##### Internal Memory Management

The package handles several complex memory management scenarios:

1. **Thread Termination**: When a thread terminates, the GC triggers finalizers to clean up associated values
2. **Manual Detachment**: Values can be explicitly detached, releasing references early
3. **Reference Cycles**: Careful weak reference usage prevents cycles that could cause memory leaks

#### API Details and Usage Patterns

The ThreadStorageMap API provides several key operations, each with specific semantics:

##### Lookup Operations

```haskell
lookup :: ThreadStorageMap a -> IO (Maybe a)
lookupOnThread :: ThreadStorageMap a -> ThreadId -> IO (Maybe a)
```

- Retrieve the value associated with current/specific thread
- Return `Nothing` if no value is associated
- Thread-safe and non-blocking
- No side effects on the map structure

##### Attachment Operations

```haskell
attach :: ThreadStorageMap a -> a -> IO (Maybe a)
attachOnThread :: ThreadStorageMap a -> ThreadId -> a -> IO (Maybe a)
```

- Associate a value with current/specific thread
- Return any previously associated value
- Register appropriate finalizers for cleanup
- Ensure thread-safety across concurrent operations

##### Detachment Operations

```haskell
detach :: ThreadStorageMap a -> IO (Maybe a)
detachFromThread :: ThreadStorageMap a -> ThreadId -> IO (Maybe a)
```

- Remove value associated with current/specific thread
- Return the removed value if it existed
- Release references to allow for earlier garbage collection
- Ensure thread-safety across concurrent operations

##### Update Operations

```haskell
update :: ThreadStorageMap a -> (Maybe a -> (IO a, b)) -> IO b
updateOnThread :: ThreadStorageMap a -> ThreadId -> (Maybe a -> (IO a, b)) -> IO b
```

- Most general operation - allows atomic reading and writing
- Takes a function that receives the current value and returns a new value plus a result
- Atomic with respect to other operations on the same thread's value
- Allows for complex transformations with minimal locking

#### Usage Recommendations

The thread-utils-context package documentation provides these important usage recommendations, which OpenTelemetry follows:

1. **Caution with ThreadId References**: Don't retain ThreadId references indefinitely, as this could delay cleanup
2. **Prefer Adjustment**: When modifying existing values, use `update` rather than `detach` followed by `attach`
3. **Cross-Thread Coordination**: When using cross-thread operations, ensure proper synchronization with the target thread
4. **Monitoring**: For long-running applications, occasionally check `storedItems` to detect potential leaks

#### NOINLINE Pragmas

You'll notice `{-# NOINLINE threadContextMap #-}` in the ThreadLocal module. This pragma:

- Prevents GHC from inlining the definition at compile time
- Ensures a single global instance of the ThreadContextMap exists
- Maintains consistent behavior across module boundaries

#### unsafePerformIO Usage

The use of `unsafePerformIO` to create the global ThreadContextMap:

- Creates the map once at module initialization time
- Makes it accessible throughout the program's lifetime without passing it as a parameter
- Is safe in this context because it's only called once and doesn't depend on other state

## API Functions and Usage

### Basic Context Manipulation

```haskell
-- Create a new key
newKey :: (MonadIO m) => Text -> m (Key a)

-- Create an empty context
empty :: Context

-- Insert a value into a context
insert :: Key a -> a -> Context -> Context

-- Look up a value in a context
lookup :: Key a -> Context -> Maybe a

-- Delete a value from a context
delete :: Key a -> Context -> Context
```

### Thread-Local Context Management

```haskell
-- Get current thread's context (or empty if none exists)
getContext :: (MonadIO m) => m Context

-- Look up current thread's context
lookupContext :: (MonadIO m) => m (Maybe Context)

-- Attach a context to current thread
attachContext :: (MonadIO m) => Context -> m (Maybe Context)

-- Detach context from current thread
detachContext :: (MonadIO m) => m (Maybe Context)

-- Modify current thread's context
adjustContext :: (MonadIO m) => (Context -> Context) -> m ()
```

### Cross-Thread Context Operations

The library also provides functions to manipulate contexts on specific threads:

```haskell
lookupContextOnThread :: (MonadIO m) => ThreadId -> m (Maybe Context)
attachContextOnThread :: (MonadIO m) => ThreadId -> Context -> m (Maybe Context)
detachContextFromThread :: (MonadIO m) => ThreadId -> m (Maybe Context)
adjustContextOnThread :: (MonadIO m) => ThreadId -> (Context -> Context) -> m ()
```

**Important Note**: These cross-thread functions should be used with caution, as there's no guarantee about what work the remote thread has done yet. They should be used only with specific cross-thread coordination mechanisms.

## Context Lifecycle Management in Multithreaded Applications

Managing context correctly in multithreaded Haskell applications requires understanding the lifecycle of contexts and threads.

### Lifecycle Rules

1. A context attached to a `ThreadId` remains alive at least as long as the `ThreadId` itself
2. Values can be freely detached from a `ThreadId` without negative consequences
3. Once all references to a `ThreadId` are dropped, the associated context may be garbage collected

### Common Pitfalls and Solutions

#### 1. Missing Context in Forked Threads

**Problem**: When forking a new thread, the context from the parent thread doesn't automatically propagate.

**Solution**: Explicitly retrieve and attach the context in the child thread:

```haskell
import Control.Concurrent
import OpenTelemetry.Context
import OpenTelemetry.Context.ThreadLocal

forkWithContext :: IO () -> IO ThreadId
forkWithContext action = do
  parentContext <- getContext
  forkIO $ do
    -- Attach parent's context to the child thread
    void $ attachContext parentContext
    action
```

#### 2. Context Pollution with Long-Lived Threads

**Problem**: Continually attaching/detaching contexts in long-lived threads can lead to accumulation of finalizers.

**Solution**: Use `adjustContext` instead of detach/attach:

```haskell
-- Inefficient pattern (creates multiple finalizers):
detachContext
attachContext newContext

-- Better approach (modifies in-place):
adjustContext (const newContext)
```

#### 3. Risk of Context Leaks

**Problem**: Retaining `ThreadId` references longer than needed can delay context cleanup.

**Solution**: Avoid storing `ThreadId` references unnecessarily:

```haskell
-- Problematic:
threadIds <- mapM forkIO actions
-- Later using threadIds causes contexts to be retained...

-- Better approach with automatic cleanup:
mapM_ forkIO actions
-- Thread IDs not kept, allowing garbage collection
```

#### 4. Thread Pool Considerations

When using thread pools, special care must be taken to maintain proper context propagation:

```haskell
withPooledWorker :: Context -> (Context -> IO a) -> IO a
withPooledWorker ctx action = do
  -- Store the original context of the worker thread
  originalCtx <- getContext
  -- Install the requested context for the duration of the action
  attachContext ctx
  result <- action ctx `finally` do
    -- Restore the original context when done
    attachContext originalCtx
  pure result
```

### Propagation Between Services

For distributed applications that communicate across service boundaries:

1. Extract the current context when sending requests
2. Use appropriate propagators (W3C TraceContext, B3, etc.) to encode the context
3. On the receiving end, extract and restore the context from request headers
4. Ensure all spans created within the service execution are children of the received context

Example:

```haskell
makeRemoteRequest :: Request -> IO Response
makeRemoteRequest req = do
  -- Get current context
  ctx <- getContext
  
  -- Extract relevant context using a propagator
  headers <- extractHeaders ctx
  
  -- Add context headers to request
  let reqWithContext = addHeaders headers req
  
  -- Make the actual request
  httpRequest reqWithContext

-- On the receiving end
handleRequest :: Request -> IO Response
handleRequest req = do
  -- Extract context from headers
  let headers = getRequestHeaders req
  ctx <- extractContextFromHeaders headers
  
  -- Install context for this thread
  void $ attachContext ctx
  
  -- Process request with proper context inheritance
  processRequest req
```

## Advanced Topics

### Context and Exceptions

Contexts do not automatically propagate across exception boundaries. When using exception handling, ensure context is properly restored:

```haskell
withLocalContext :: Context -> IO a -> IO a
withLocalContext ctx action = bracket
  (do
    oldCtx <- getContext
    attachContext ctx
    pure oldCtx)
  (attachContext)
  (const action)
```

### Thread-Local vs. Explicit Context Passing

OpenTelemetry provides two styles of context propagation:

1. **Thread-local context**: 
   - Implicit propagation using thread-local storage
   - Convenient but can lead to "invisible" dependencies
   - Default approach in the Haskell implementation

2. **Explicit context passing**:
   - Passing Context as a parameter
   - More explicit and functional style
   - Useful for pure code or applications with complex threading models

Example of explicit context passing:

```haskell
processOrder :: Context -> Order -> IO Result
processOrder ctx order = do
  let span = lookupSpan ctx
  -- Use span and other context values explicitly
  -- ...
```

## Best Practices

1. **Explicitly propagate context to forked threads**: Always ensure child threads receive the parent's context.

2. **Use context-aware wrappers for async operations**: Create utilities that automatically propagate context.

3. **Clean up contexts when done**: For very long-lived applications, explicitly detach contexts that are no longer needed.

4. **Keep thread creation and context manipulation close**: Handle context immediately after thread creation to prevent mistakes.

5. **Consider a monad transformer stack**: For complex applications, using a `ReaderT Context IO` pattern can simplify context management.

6. **Use the lens interface when appropriate**: If you have complex nested contexts, the `contextL` lens can simplify manipulation.

7. **Document context requirements**: Make it clear which functions expect what context to be present.

### Common Usage Patterns with thread-utils-context

Here are important design patterns that leverage the thread-utils-context package's capabilities effectively:

#### 1. Thread-Aware Action Wrappers

Create utilities that ensure context propagation:

```haskell
-- Execute an action with parent thread's context
withParentContext :: IO a -> IO a
withParentContext action = do
  parentCtx <- getContext
  -- Create a new thread that inherits the parent context
  withAsync (do
    attachContext parentCtx
    action) wait

-- Run an async computation with current context
asyncWithContext :: IO a -> IO (Async a)
asyncWithContext action = do
  ctx <- getContext
  async $ do
    attachContext ctx
    action
```

#### 2. Context Stack Management

Thread-utils-context supports a "context stack" pattern for nested operations:

```haskell
-- Run an action with a modified context, restoring the original after
withLocalContext :: (Context -> Context) -> IO a -> IO a
withLocalContext f action = bracket
  (do
    original <- getContext
    let modified = f original
    attachContext modified
    return original)
  attachContext
  (const action)

-- Example: Add a span to the context for the duration of an action
withSpan :: Span -> IO a -> IO a
withSpan span = withLocalContext (insertSpan span)
```

#### 3. Worker Pool Context Management

When using worker pools, ensure workers properly handle context:

```haskell
-- Create a worker that properly manages context through job execution
contextAwareWorker :: TQueue (Context, IO a, TMVar a) -> IO ()
contextAwareWorker jobQueue = forever $ do
  (ctx, job, resultVar) <- atomically $ readTQueue jobQueue
  -- Store original worker context for restoration
  originalCtx <- getContext
  
  -- Install job's context for execution
  attachContext ctx
  
  -- Execute job and capture result
  result <- job `finally` attachContext originalCtx
  
  -- Return result
  atomically $ putTMVar resultVar result
```

#### 4. Background Thread Context Propagation

For background services, explicitly manage context propagation:

```haskell
-- Start a background service with the current context
startBackgroundService :: IO () -> IO ThreadId
startBackgroundService service = do
  ctx <- getContext
  forkIO $ do
    attachContext ctx
    service
```

#### 5. Monitoring Context Usage

For long-running applications, monitor for potential context leaks:

```haskell
-- Periodically check for potential context leaks
monitorContextUsage :: ThreadContextMap -> Int -> IO ()
monitorContextUsage tcMap intervalSeconds = void $ forkIO $ forever $ do
  -- Wait for interval
  threadDelay (intervalSeconds * 1000000)
  
  -- Get all stored contexts
  items <- storedItems tcMap
  
  -- Log if the number seems suspiciously high
  when (length items > 1000) $ 
    putStrLn $ "Warning: High number of thread contexts: " ++ show (length items)
```

## Performance Considerations

When using Context in high-performance applications, be aware of these performance characteristics:

1. **Context Creation**: Creating Context objects is relatively cheap, but not free. Avoid creating many short-lived contexts.

2. **Key Creation**: Creating new Keys with `newKey` requires IO and is relatively expensive. Keys should be created at startup and reused.

3. **Lookup Operations**: Lookups in Vault are O(log n) operations. If very frequent lookups of the same keys are needed, consider caching the results.

4. **Thread-Local Storage Access**: Access to thread-local storage involves some overhead. For extremely performance-sensitive code paths, consider explicit context passing.

5. **Context Size**: As contexts grow in size, lookup and manipulation operations become more expensive. Keep contexts reasonably sized.

### Memory Management

The Context implementation is designed to prevent most memory leaks through:

1. **Weak References**: The thread-local storage uses weak references to prevent contexts from keeping threads alive.

2. **Automatic Cleanup**: Finalizers automatically clean up thread-local contexts when threads are garbage collected.

3. **Strict Evaluation**: The strict Vault implementation prevents thunk buildup that could lead to space leaks.

However, to ensure optimal memory usage, especially in long-running applications:

- Avoid keeping references to `ThreadId` objects longer than necessary
- Be careful about storing large data structures directly in Context (consider using references)
- For very long-lived threads, consider explicitly detaching unused contexts when they're no longer needed

## Debugging Context

When developing and troubleshooting applications that use OpenTelemetry's Context system, it's important to have techniques for inspecting context contents. Here are several approaches for debugging contexts:

### 1. Inspecting a Context Instance

Contexts don't have a `Show` instance by default because their contents are heterogeneous. However, you can create helper functions to extract and display the known components:

```haskell
-- Example: you can write a utility for debugging context contents
-- (this is not provided by the library)
debugContext :: Context -> IO ()
debugContext ctx = do
  putStrLn "Context Debug Information:"
  
  -- Check for span
  case lookupSpan ctx of
    Just span -> do
      spanCtx <- getSpanContext span
      -- SpanId and TraceId already have Show instances that produce nice output
      putStrLn $ "  Span: " ++ show (spanId spanCtx) ++ " (Trace: " ++ show (traceId spanCtx) ++ ")"
      putStrLn $ "  Is sampled: " ++ show (isSampled (traceFlags spanCtx))
      putStrLn $ "  Is remote: " ++ show (isRemote spanCtx)
    Nothing -> putStrLn "  No active span"
  
  -- Check for baggage
  case lookupBaggage ctx of
    Just baggage -> do
      putStrLn $ "  Baggage items: " ++ show (length (baggageItems baggage))
      forM_ (baggageItems baggage) $ \(k, v) ->
        putStrLn $ "    " ++ show k ++ ": " ++ show v
    Nothing -> putStrLn "  No baggage"
  
  -- Additional diagnostic info as needed
  putStrLn "  (Other context values not shown)"
```

### 2. Tracking Context Flow in Multithreaded Applications

To track context propagation across thread boundaries, you can create wrappers that log context information:

```haskell
forkWithContextLogging :: IO () -> IO ThreadId
forkWithContextLogging action = do
  parentCtx <- getContext
  threadId <- myThreadId
  putStrLn $ "Thread " ++ show threadId ++ " forking with context"
  debugContext parentCtx
  
  forkIO $ do
    void $ attachContext parentCtx
    childThreadId <- myThreadId
    putStrLn $ "Thread " ++ show childThreadId ++ " received context"
    childCtx <- getContext
    debugContext childCtx
    action
```

### 3. Using Key Names for Identification

When creating custom keys, use descriptive names to make debugging easier:

```haskell
-- Instead of this:
myKey <- newKey "data"

-- Use something more specific and identifiable:
myKey <- newKey "customer-preferences-v2"
```

The `keyName` field is directly accessible from a `Key` and can be used in logging to identify what types of values a context contains.

### 4. Dumping All Context Keys

For advanced debugging, you can create a utility that shows all the key names in a context:

```haskell
-- Note: This is hypothetical example code, not a library function.
-- Requires internal access to the Vault structure which is not publicly exposed.
dumpContextKeys :: Context -> IO [Text]
dumpContextKeys (Context vault) = do
  -- This cannot be fully implemented as Vault doesn't expose iteration
  -- or maintain a registry of created keys
  -- Return list of key names from context
  -- ...
```

### 5. Thread Context Inspection

For debugging issues with thread-local context propagation, examine which threads have contexts attached:

```haskell
-- Import internal modules with care
import OpenTelemetry.Context.ThreadLocal (threadContextMap)
import Data.Thread.Storage.Map (storedItems)

-- Report on all threads that have contexts
dumpAllThreadContexts :: IO ()
dumpAllThreadContexts = do
  items <- storedItems threadContextMap
  putStrLn $ "Total threads with contexts: " ++ show (length items)
  forM_ items $ \(tid, ctx) -> do
    putStrLn $ "Thread " ++ show tid ++ " has context:"
    debugContext ctx
```

### 6. Context Comparison

When debugging propagation issues, it can be useful to compare contexts:

```haskell
-- Example: compare two contexts (not a library function)
-- Focuses on known values like spans and baggage
compareContexts :: Context -> Context -> IO ()
compareContexts ctx1 ctx2 = do
  putStrLn "Context comparison:"
  
  -- Compare spans
  let span1 = lookupSpan ctx1
  let span2 = lookupSpan ctx2
  
  spanComparisonResult <- case (span1, span2) of
    (Just s1, Just s2) -> do
      sc1 <- getSpanContext s1
      sc2 <- getSpanContext s2
      -- Compare the core identifying fields of spans
      let idMatch = spanId sc1 == spanId sc2 && traceId sc1 == traceId sc2
      let flagsMatch = traceFlags sc1 == traceFlags sc2
      
      when (not idMatch) $
        putStrLn $ "  Span IDs differ: " ++ show (spanId sc1) ++ " vs " ++ show (spanId sc2)
      
      when (not flagsMatch) $
        putStrLn $ "  Trace flags differ: sampled=" ++ show (isSampled (traceFlags sc1)) 
                  ++ " vs sampled=" ++ show (isSampled (traceFlags sc2))
      
      pure $ idMatch && flagsMatch
    (Nothing, Nothing) -> pure True
    (Just _, Nothing) -> do
      putStrLn "  First context has a span, second doesn't"
      pure False
    (Nothing, Just _) -> do
      putStrLn "  Second context has a span, first doesn't"
      pure False
  
  -- Compare baggage
  let baggage1 = lookupBaggage ctx1
  let baggage2 = lookupBaggage ctx2
  
  when (isJust baggage1 /= isJust baggage2) $
    putStrLn $ "  Baggage presence differs: " ++ show (isJust baggage1) ++ " vs " ++ show (isJust baggage2)
    
  when ((isJust baggage1 && isJust baggage2) && (baggageItems <$> baggage1 /= baggageItems <$> baggage2)) $ do
    putStrLn "  Baggage items differ:"
    case (baggage1, baggage2) of
      (Just b1, Just b2) -> do
        let items1 = baggageItems b1
        let items2 = baggageItems b2
        let onlyIn1 = filter (\(k,_) -> not $ any (\(k2,_) -> k == k2) items2) items1
        let onlyIn2 = filter (\(k,_) -> not $ any (\(k2,_) -> k == k2) items1) items2
        
        unless (null onlyIn1) $ do
          putStrLn "    Only in first context:"
          forM_ onlyIn1 $ \(k,v) -> putStrLn $ "      " ++ show k ++ ": " ++ show v
          
        unless (null onlyIn2) $ do
          putStrLn "    Only in second context:"
          forM_ onlyIn2 $ \(k,v) -> putStrLn $ "      " ++ show k ++ ": " ++ show v
      _ -> pure ()
  
  -- Add comparison of other important context values
```

### Best Practices for Context Debugging

1. **Develop a context debugging utility module** with functions like those shown above, customized for your application's specific context usage.

2. **Log context information at key boundaries** in your application, especially when:
   - Receiving requests
   - Making outbound calls
   - Forking threads
   - Resuming from asynchronous operations

3. **Add instrumentation conditionally** using environment variables, so debug code doesn't impact production performance.

4. **Keep track of custom keys** in a central location to make context debugging more comprehensive.

5. **Consider a visual representation** for complex context propagation paths in large applications.

Remember that context debugging utilities may need access to internal modules or structures. Use these techniques during development and testing, but be cautious about including them in production code.

## Conclusion

The OpenTelemetry Context implementation in Haskell leverages GHC internals and Haskell's strong type system to provide a robust mechanism for maintaining trace continuity across thread boundaries. By properly managing context in multithreaded applications, you can achieve distributed tracing that accurately represents the execution flow of your application, even across service boundaries.

While the implementation includes some "unsafe" elements internally, the exposed API is safe and provides strong guarantees about context lifecycle. Understanding the underlying mechanics will help you avoid common pitfalls and build observable systems that properly propagate telemetry data across your entire application ecosystem.

The use of Vault provides a solid foundation for type-safe heterogeneous storage, making the Context implementation both flexible and robust. This careful design enables OpenTelemetry to provide powerful distributed tracing capabilities while maintaining the type safety and performance characteristics that Haskell applications expect.
