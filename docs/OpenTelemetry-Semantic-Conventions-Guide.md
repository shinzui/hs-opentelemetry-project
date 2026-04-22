# OpenTelemetry Semantic Conventions for Haskell

This guide explains `hs-opentelemetry-semantic-conventions`, a library of typed attribute keys generated from the upstream [OpenTelemetry semantic-conventions](https://github.com/open-telemetry/semantic-conventions/) specification. It lets instrumentation record attributes whose names match the cross-language conventions that backends, dashboards, and analysis tools expect, without hand-typing strings like `"http.request.method"` at every call site.

## Table of Contents

- [What the Package Provides](#what-the-package-provides)
- [Installation](#installation)
- [The `AttributeKey` Type](#the-attributekey-type)
- [Using Attribute Keys](#using-attribute-keys)
- [Module Organization and Naming](#module-organization-and-naming)
- [Finding the Key You Need](#finding-the-key-you-need)
- [Regenerating the Module](#regenerating-the-module)
- [Versioning and Upstream Spec](#versioning-and-upstream-spec)

## What the Package Provides

The library exposes a single module, `OpenTelemetry.SemanticConventions`, containing roughly four hundred top-level `AttributeKey a` values drawn from the OpenTelemetry semantic conventions spec. Each key:

- Is phantom-typed with the expected Haskell type for its value (e.g. `AttributeKey Text`, `AttributeKey Int64`, `AttributeKey Bool`).
- Wraps the canonical dotted attribute name (`"http.request.method"`, `"db.system"`, `"messaging.destination.name"`, ...) so backends see the exact strings the spec defines.
- Carries a Haddock comment summarizing the attribute's meaning and any requirement level (`required`, `conditionally required`, `opt-in`).

The module groups keys and their associated specifications under Haddock sections — spans for HTTP clients and servers, database calls, messaging producers/consumers, FaaS invocations, Kubernetes resources, cloud providers, JVM metrics, RPC metrics, and so on — mirroring the upstream YAML model.

## Installation

Add the package to your instrumentation library's `build-depends`:

```cabal
build-depends:
  , hs-opentelemetry-api
  , hs-opentelemetry-semantic-conventions
```

It only depends on `hs-opentelemetry-api` and `text`, so it is safe to depend on from any instrumentation or SDK-adjacent package without pulling in exporters or the SDK.

## The `AttributeKey` Type

`AttributeKey` is defined in the API package as:

```haskell
newtype AttributeKey a = AttributeKey { unkey :: Text }
```

The type parameter `a` records the Haskell type the key expects its value to be. Because the spec standardizes both the name and the value type, this lets the compiler catch mistakes like stashing an `Int` under `"server.address"` or a `Text` under `"server.port"`.

The semantic-conventions module builds keys like:

```haskell
server_address :: AttributeKey Text
server_address = AttributeKey "server.address"

server_port :: AttributeKey Int64
server_port = AttributeKey "server.port"

jvm_thread_daemon :: AttributeKey Bool
jvm_thread_daemon = AttributeKey "jvm.thread.daemon"
```

You never construct these yourself — import them from `OpenTelemetry.SemanticConventions` and feed them to the API functions that accept `AttributeKey`.

## Using Attribute Keys

### Recording on a span directly

`OpenTelemetry.Trace.Core` exposes `addAttribute` and `addAttributes` that take a plain `Text` key. To use a typed `AttributeKey`, go through the key's `unkey` field or the attribute map helpers that accept `AttributeKey` directly.

The typical pattern in instrumentation code is to build an `AttributeMap` via `insertAttributeByKey` and pass it into `SpanArguments`:

```haskell
import OpenTelemetry.Attributes.Map (AttributeMap, insertAttributeByKey)
import OpenTelemetry.SemanticConventions
  ( messaging_destination_name
  , messaging_kafka_destination_partition
  , messaging_operation
  )
import OpenTelemetry.Trace.Core
  ( SpanArguments (kind)
  , SpanKind (Producer)
  , addAttributesToSpanArguments
  , callerAttributes
  , defaultSpanArguments
  , toAttribute
  )

producerAttrs :: Text -> Int64 -> AttributeMap
producerAttrs topic partition =
  ( insertAttributeByKey messaging_operation ("send" :: Text)
  . insertAttributeByKey messaging_destination_name topic
  . insertAttributeByKey messaging_kafka_destination_partition partition
  ) callerAttributes

spanArgs :: Text -> Int64 -> SpanArguments
spanArgs topic partition =
  addAttributesToSpanArguments
    (producerAttrs topic partition)
    defaultSpanArguments { kind = Producer }
```

The `hs-opentelemetry-instrumentation-hw-kafka-client` package uses exactly this pattern — see its `producerAttributes` and `consumerAttributes` helpers for a real example.

### Picking the right attribute

Each key is Haddocked with a short description sourced from the upstream YAML. Section-level Haddock comments also list the keys applicable to a given span kind and call out requirement levels, e.g.:

```
{- $trace_http_server
Semantic Convention for HTTP Server

=== Attributes
- 'http_route'
- 'server_address'
- 'server_port'
- 'url_path'            -- Requirement level: required
- 'url_query'           -- Requirement level: conditionally required: If and only if one was received/sent.
- 'url_scheme'
-}
```

Follow the requirement levels when deciding what to record: `required` attributes should always be populated when the span is produced, `conditionally required` attributes only when their condition holds, and `opt-in` attributes only when the user explicitly asks for them.

## Module Organization and Naming

### Identifier conventions

Upstream attribute names are dotted lowercase (e.g. `http.request.method`, `messaging.kafka.message.key`, `aws.ecs.task.arn`). The generator rewrites them to Haskell identifiers by:

- Replacing dots with underscores.
- Camel-casing path segments that contain dashes, underscores, or reserved words, so the result is a valid Haskell identifier that still round-trips to the spec name.

The dotted string in the `AttributeKey` value is always the authoritative name — it is what ends up on the wire and in backends. The Haskell identifier is a local alias.

Examples:

| Spec name | Haskell identifier |
| --- | --- |
| `http.request.method` | `http_request_method` |
| `messaging.kafka.message.key` | `messaging_kafka_message_key` |
| `faas.invocation_id` | `faas_invocationId` |
| `network.peer.address` | `network_peer_address` |
| `k8s.deployment.name` | `k8s_deployment_name` |

### Domains covered

Sections in the generated module mirror the upstream `model/` tree. At a high level you will find keys for:

- HTTP clients and servers (`http_*`, `url_*`, `server_*`, `client_*`, `network_*`, `user_agent_*`).
- Databases (`db_*`), messaging systems (`messaging_*`, including Kafka, RabbitMQ, and Kinesis specifics), RPC (`rpc_*`).
- FaaS and cloud providers (`faas_*`, `cloud_*`, `aws_*`, `gcp_*`, `azure_*`, `heroku_*`).
- Kubernetes resources (`k8s_*`).
- Runtime and host metrics (`jvm_*`, `process_*`, `system_*`, `host_*`, `device_*`, `os_*`).
- Identity and peer (`enduser_*`, `peer_*`).

Browse the module's section list (the export list at the top) for a full index — each section header corresponds to a group in the upstream spec.

## Finding the Key You Need

The module is large (around 9,300 lines). Three practical ways to locate a key:

1. **Start from the upstream docs.** Find the attribute you want on [opentelemetry.io/docs/specs/semconv](https://opentelemetry.io/docs/specs/semconv/), then translate the dotted name to a Haskell identifier by replacing `.` with `_` and camel-casing anything that would otherwise collide with a keyword.
2. **Grep the module.** `grep 'AttributeKey "http.request'` inside `semantic-conventions/src/OpenTelemetry/SemanticConventions.hs` will surface the matching exports.
3. **Use the Haddock section headers.** The module's export list groups keys by span/metric convention, so `-- * trace.http.server` will lead you to every key relevant to server HTTP spans.

If a spec attribute is missing, the generator or its input model is out of date — see [Regenerating the Module](#regenerating-the-module).

## Regenerating the Module

The module is produced by an executable in this package. The top-level `Makefile` drives it:

```make
YAML_FILES := $(shell find model/model -type f -name "*.yml" -o -name "*.yaml")

build: src/OpenTelemetry/SemanticConventions.hs
    cabal build hs-opentelemetry-semantic-conventions:libs

src/OpenTelemetry/SemanticConventions.hs: hs-opentelemetry-semantic-conventions.cabal dev/generate.hs $(YAML_FILES)
    cabal run hs-opentelemetry-semantic-conventions:exe:generate
```

To regenerate after updating the upstream spec:

1. Drop the latest spec YAML files into `semantic-conventions/model/model/`. (The upstream repo's `model/` directory is the canonical source.)
2. From `semantic-conventions/`, run `make` (or `cabal run hs-opentelemetry-semantic-conventions:exe:generate`). This reads every `*.yml` / `*.yaml` file under `model/`, parses it with `Data.Yaml` and the schema defined at the top of `dev/generate.hs`, and rewrites `src/OpenTelemetry/SemanticConventions.hs` in place. The output file begins with a `DO NOT EDIT` banner — never modify it by hand.
3. Commit both the updated `model/` tree and the regenerated `SemanticConventions.hs`.

The generator is a standalone Haskell program; it depends on `aeson`, `yaml`, `Glob`, `directory`, `filepath`, `text`, `unordered-containers`, and `vector`. See `dev/generate.hs` for the schema types and emission logic.

## Versioning and Upstream Spec

The package's cabal description and module header currently pin to semantic-conventions **v1.24**:

> OpenTelemetry Semantic Conventions for Haskell is a library that is automatically generated based on [semantic-conventions](https://github.com/open-telemetry/semantic-conventions/) v1.24.

When bumping to a newer upstream version:

- Replace the model YAML with the newer revision.
- Regenerate (see above).
- Update the `synopsis` / `description` in `hs-opentelemetry-semantic-conventions.cabal` and the Haddock banner in the generated module to record the new version.
- Review the diff carefully: semantic-conventions frequently renames or deprecates attributes between releases (for example, the `net.*` → `network.*` migration), and downstream instrumentation must be updated in lockstep.

Because the module is regenerated wholesale on each version bump, any downstream code that imports a since-renamed key will fail to compile, which is the intended signal to migrate.
