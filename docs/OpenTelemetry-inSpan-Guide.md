# OpenTelemetry inSpan Guide

This guide documents the different variants of `inSpan` functions available in the OpenTelemetry Haskell library, along with their specific use cases.

## Overview

The `inSpan` family of functions provides different ways to create and manage spans in your application. Each variant has specific strengths:

- **`inSpan`**: Simple API when you just need to trace an operation
- **`inSpan'`**: When you need access to the span for direct manipulation
- **`inSpan''`**: Most general form giving complete control over the span

## Core API Variants

### `inSpan`

```haskell
inSpan :: (MonadUnliftIO m, HasCallStack)
       => Tracer
       -> Text        -- The name of the span
       -> SpanArguments
       -> m a         -- The action to perform
       -> m a
```

**Purpose**:
- Creates a span with the given name and arguments
- Runs the provided action within the context of this span
- Automatically infers source code attributes from the call stack
- Handles exceptions by recording them in the span and rethrowing them
- Automatically ends the span when the action completes

**Example**:
```haskell
result <- inSpan tracer "fetch-data" defaultSpanArguments $ do
  -- Operation to be traced
  fetchDataFromDatabase
```

### `inSpan'`

```haskell
inSpan' :: (MonadUnliftIO m, HasCallStack)
        => Tracer
        -> Text       -- The name of the span
        -> SpanArguments
        -> (Span -> m a)  -- Action that takes the created span
        -> m a
```

**Purpose**:
- Similar to `inSpan` but passes the created span to the action
- This allows the action to directly interact with the span (e.g., add attributes or events)
- Automatically infers source code attributes from the call stack

**Example**:
```haskell
result <- inSpan' tracer "process-data" defaultSpanArguments $ \span -> do
  -- Can use the span directly
  addAttribute span "data.size" dataSize
  processData
```

### `inSpan''`

```haskell
inSpan'' :: (MonadUnliftIO m, HasCallStack)
         => Tracer
         -> Text      -- The name of the span
         -> SpanArguments
         -> (Span -> m a)  -- Action that takes the created span
         -> m a
```

**Purpose**:
- The most general version that both other variants build upon
- Creates a span, attaches it to the current context, and passes it to the action
- Handles cleanup and error recording
- Does not automatically add caller attributes (unlike the other variants)

**Example**:
```haskell
result <- inSpan'' tracer "raw-operation" spanArgs $ \span -> do
  -- Custom span handling
  updateName span "better-name"
  performOperation
```

## Monad API Variants

For applications using a monad stack that implements `MonadTracer`, these variants eliminate the need to pass a tracer explicitly.

### `inSpan` (Monad variant)

```haskell
inSpan :: (MonadUnliftIO m, MonadTracer m, HasCallStack)
       => Text       -- The name of the span
       -> SpanArguments
       -> m a        -- The action to perform
       -> m a
```

**Example**:
```haskell
-- In a monad that implements MonadTracer
result <- inSpan "database-query" defaultSpanArguments $ do
  runDatabaseQuery
```

### `inSpan'` (Monad variant)

```haskell
inSpan' :: (MonadUnliftIO m, MonadTracer m, HasCallStack)
        => Text      -- The name of the span
        -> SpanArguments
        -> (Span -> m a)  -- Action that takes the created span
        -> m a
```

### `inSpan''` (Monad variant)

```haskell
inSpan'' :: (MonadUnliftIO m, MonadTracer m, HasCallStack)
         => Text     -- The name of the span
         -> SpanArguments
         -> (Span -> m a)  -- Action that takes the created span
         -> m a
```

## Source Code Attributes

### `callerAttributes`

Automatically added by the `inSpan` and `inSpan'` functions (but not by `inSpan''`). These attributes describe where the function is called from:

- `code.function`: The name of the calling function
- `code.namespace`: The module of the calling code
- `code.filepath`: The file containing the calling code
- `code.lineno`: The line number of the call
- `code.package`: The package name

### `ownCodeAttributes`

Similar to `callerAttributes` but captures the current function's information. Useful when implementing custom span creation functions where `callerAttributes` would capture the wrong location.

### `srcAttributes`

The underlying function that powers both `callerAttributes` and `ownCodeAttributes`. It takes a `CallStack` and produces source code location attributes.

## When to Use Each Variant

1. **Use `inSpan` when**:
   - You only need to trace the execution of a function
   - You don't need direct access to the span

2. **Use `inSpan'` when**:
   - You need to add custom attributes, events, or links to the span
   - You want to update the span status or name during execution

3. **Use `inSpan''` when**:
   - You need complete control over the span's attributes
   - You're implementing a custom tracing function
   - You want to avoid automatic caller attributes

4. **Use the Monad variants when**:
   - Your application uses a monad stack that implements `MonadTracer`
   - You want to avoid passing the tracer explicitly

## Parent-Child Span Relationship

In distributed tracing, spans are often organized in a parent-child hierarchy to represent nested operations. There are several ways to associate a span with a parent span:

### 1. Implicit Parent from Current Context

The most common approach is to let OpenTelemetry automatically use the active span in the current context as the parent:

```haskell
-- The outer span becomes the parent of the inner span
inSpan tracer "parent-operation" defaultSpanArguments $ do
  -- Some work
  inSpan tracer "child-operation" defaultSpanArguments $ do
    -- Child operation work
```

When you create a span inside another span like this, the outer span is automatically set as the parent of the inner span through the context system.

### 2. Using Context with Parent Span

You can also manipulate the context directly to set up the parent-child relationship:

```haskell
inSpan' tracer "parent-operation" defaultSpanArguments $ \parentSpan -> do
  -- Get current context
  currentCtx <- currentContext
  
  -- Create new context with parent span
  let ctxWithParent = insertSpan parentSpan currentCtx
  
  -- Run child operation with this context
  runInContext ctxWithParent $ do
    inSpan tracer "child-operation" defaultSpanArguments $ do
      -- Child operation work
```

This approach is particularly useful for cross-thread or asynchronous operations where you need to explicitly manage context.

### 3. Creating Links Instead of Parents

For certain scenarios where a full parent-child relationship isn't appropriate (like in fan-out/fan-in patterns), you can use links:

```haskell
-- Get the context of an existing span
parentCtx <- getSpanContext parentSpan

-- Create a new span with a link to the parent
let linkToParent = NewLink { linkContext = parentCtx, linkAttributes = [] }
    args = defaultSpanArguments { links = [linkToParent] }
    
inSpan tracer "linked-operation" args $ do
  -- Operation work
```

Links create a reference between spans without the strict parent-child hierarchical relationship.

## Best Practices

1. **Use the simplest variant** that meets your needs
2. **Consider attribute sources** - be aware that adding your own source attributes will prevent automatic ones
3. **For large applications**, consider implementing `MonadTracer` for your monad stack
4. **Remember that error handling** is built into all variants
5. **For context propagation** across threads, ensure proper context propagation with the appropriate context management functions
6. **Use nested spans** when possible for simpler parent-child relationships
7. **Use explicit context manipulation** when working with asynchronous code or across thread boundaries

## Custom Implementation Example

Creating a helper for a specific application context:

```haskell
-- Custom helper that simplifies span creation in your application
inSpan :: (MonadUnliftIO m, HasCallStack) => Text -> SpanArguments -> m a -> m a
inSpan name args act = do
  tp <- getGlobalTracerProvider
  let tracer = makeTracer tp $(detectInstrumentationLibrary) tracerOptions
  Trace.inSpan tracer name args act
```

This approach reduces boilerplate by encapsulating tracer creation and configuration.
