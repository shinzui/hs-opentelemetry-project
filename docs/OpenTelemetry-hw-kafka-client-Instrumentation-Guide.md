# OpenTelemetry hw-kafka-client Instrumentation Guide

This guide explains how to use `hs-opentelemetry-instrumentation-hw-kafka-client` to add distributed tracing to Kafka producers and consumers built with [hw-kafka-client](https://hackage.haskell.org/package/hw-kafka-client). The instrumentation wraps the standard produce and poll calls, creates OpenTelemetry spans for each messaging operation, and propagates trace context through Kafka message headers.

## What the Instrumentation Does

The package exposes two functions in `OpenTelemetry.Instrumentation.Kafka`:

- `produceMessage` — a drop-in replacement for `Kafka.Producer.produceMessage` that creates a `Producer`-kind span, records messaging attributes for the outgoing record, and injects the current trace context into the Kafka message headers.
- `pollMessage` — a drop-in replacement for `Kafka.Consumer.pollMessage` that extracts any upstream trace context from the consumed record's headers, attaches it to the thread-local context, and creates a `Consumer`-kind span describing the received message.

Both functions use the global tracer provider and the propagators that were configured on it, so the choice of propagation format (W3C TraceContext, B3, Datadog, etc.) follows whatever the application has registered.

## Installation

Add the package to your `build-depends`:

```cabal
build-depends:
  , hs-opentelemetry-api
  , hs-opentelemetry-instrumentation-hw-kafka-client
  , hw-kafka-client
```

At the application level you will typically also depend on `hs-opentelemetry-sdk` (and an exporter such as `hs-opentelemetry-exporter-otlp`) so that the global tracer provider is initialized with the propagators and exporters you want. See the main `OpenTelemetry-API-SDK-Guide.md` and `OpenTelemetry-TracerProvider-Guide.md` for tracer provider setup.

## Producer Usage

Replace direct calls to `Kafka.Producer.produceMessage` with the instrumented version:

```haskell
import qualified OpenTelemetry.Instrumentation.Kafka as OtelKafka
import Kafka.Producer

sendEvent :: KafkaProducer -> ProducerRecord -> IO (Maybe KafkaError)
sendEvent producer record =
  OtelKafka.produceMessage producer record
```

For each call, the instrumentation:

1. Creates a span named `"send <topic-name>"` with `SpanKind = Producer`.
2. Records messaging attributes (see [Recorded Attributes](#recorded-attributes)).
3. Injects the current trace context into the record's headers via the configured propagator. Any headers you set on `prHeaders` are preserved — the instrumentation appends propagation headers rather than replacing them.
4. Calls the underlying `Kafka.Producer.produceMessage` with the enriched record.

The function signature mirrors the original, so it can be swapped in without further changes.

## Consumer Usage

Wrap your poll calls the same way:

```haskell
import qualified OpenTelemetry.Instrumentation.Kafka as OtelKafka
import Kafka.Consumer

pollOne
  :: ConsumerProperties
  -> KafkaConsumer
  -> Timeout
  -> IO (Either KafkaError (ConsumerRecord (Maybe ByteString) (Maybe ByteString)))
pollOne props consumer timeout =
  OtelKafka.pollMessage props consumer timeout
```

Note the additional `ConsumerProperties` parameter — the instrumentation uses it to look up `group.id` for the `messaging.kafka.consumer_group` attribute, since hw-kafka-client does not expose a way to read the consumer's group id after construction.

For each successful poll, the instrumentation:

1. Extracts trace context from the message's headers using the configured propagator and attaches it to the thread-local context, so downstream spans in the processing handler are linked to the producer's trace.
2. Creates a span named `"process <topic-name>"` with `SpanKind = Consumer` and records messaging attributes.
3. Returns the original `ConsumerRecord` unchanged.

On a `Left err` result, no span is created and the error is returned as-is.

### Propagating Context Into Processing Code

`pollMessage` attaches the extracted context to the thread-local context before the consumer span is created, so as long as your processing code runs on the same thread (or forwards the context explicitly), calls to `inSpan` inside the handler will nest under the incoming trace.

If you hand messages off to a worker pool, capture the context inside the consumer span and reattach it on the worker thread using `OpenTelemetry.Context.ThreadLocal.attachContext`.

## Recorded Attributes

All attributes follow the OpenTelemetry messaging semantic conventions. Both sides record:

- `messaging.operation` — `"send"` for producers, `"process"` for consumers.
- `messaging.destination.name` — the topic name.
- `messaging.kafka.message.key` — the record key, when present and UTF-8 decodable.
- `messaging.kafka.destination.partition` — the partition id. On the producer side this is only recorded when `prPartition` is `SpecifiedPartition`.

Consumer spans additionally record:

- `messaging.kafka.consumer.group` — looked up from `cpProps` on the supplied `ConsumerProperties`. Omitted if `group.id` is not set.
- `messaging.kafka.message.offset` — the offset of the consumed record.

Spans are also annotated with caller attributes derived from `HasCallStack`, via `callerAttributes` from the API.

## Context Propagation Headers

Propagation uses the tracer provider's configured propagator. The instrumentation translates between Kafka's `Headers` (a list of `(ByteString, ByteString)` pairs) and the `RequestHeaders` type the propagator API expects, preserving case-insensitive header semantics.

If your application configures `hs-opentelemetry-propagator-w3c` (the default for the SDK), produced messages will carry `traceparent` (and `tracestate` when present) headers, and consumed messages will be linked to the upstream trace automatically.

## Caveats and Known Limitations

- **Consumer group lookup is a workaround.** hw-kafka-client does not expose an accessor for the consumer's group id, so the instrumentation reads it from the `ConsumerProperties` you pass in. If you construct your `ConsumerProperties` without calling the `groupId` helper, the attribute will be missing.
- **Non-UTF-8 keys are dropped.** `messaging.kafka.message.key` is only recorded when the key decodes cleanly as UTF-8. Binary keys are silently omitted from the span attributes.
- **Only the single-message APIs are wrapped.** `produceMessage` covers `Kafka.Producer.produceMessage`; `pollMessage` covers `Kafka.Consumer.pollMessage`. Batch APIs (`produceMessageBatch`, `pollMessageBatch`) are not yet instrumented — if you use them, you will need to add spans manually.
- **Consumer spans close around a no-op.** The span is created after the record has been received, so it represents the receive event rather than message handling time. If you want a span covering your processing logic, create one inside your handler using `inSpan` — it will be a child of the consumer span because the context was attached.

## Related Guides

- `OpenTelemetry-Instrumentation-Guide.md` — general patterns for building instrumentation libraries.
- `OpenTelemetry-Propagators-Guide.md` — configuring propagation formats for cross-service traces.
- `OpenTelemetry-Context-Guide.md` — how context flows through thread-local storage.
