let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/ad9960dd3dd3b33eadd45f17bcf430b0e1ec13bc/package.dhall
        sha256:83aa1432e98db5da81afde4ab2057dcab7ce4b2e883d0bc7f16c7d25b917dd0c

in  Schema.Project::{ project =
        Schema.ProjectIdentity::{ name = "hs-opentelemetry"
        , namespace = "iand675"
        , type = Schema.PackageType.Library
        , description = Some
            "Corpus: Haskell OpenTelemetry SDK, exporters, instrumentation, and propagators"
        , language = Schema.Language.Haskell
        , lifecycle = Schema.Lifecycle.Active
        , domains = [ "observability", "telemetry", "tracing" ]
        , owners = [ "iand675" ]
        , origin = Schema.Origin.ThirdParty
        }
    , repos =
      [ Schema.Repo::{ name = "hs-opentelemetry"
        , github = Some "iand675/hs-opentelemetry"
        , localPath = Some "hs-opentelemetry"
        }
      ]
    , packages =
      [ Schema.Package::{ name = "hs-opentelemetry-api"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/api"
        , description = Some "OpenTelemetry API for Haskell"
        }
      , Schema.Package::{ name = "hs-opentelemetry-sdk"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/sdk"
        , description = Some "OpenTelemetry SDK for Haskell"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-exporter-otlp"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-b3"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-datadog"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-w3c"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-otlp"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/otlp"
        , description = Some "OTLP protocol types for Haskell"
        }
      , Schema.Package::{ name = "hs-opentelemetry-semantic-conventions"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/semantic-conventions"
        , description = Some "OpenTelemetry semantic conventions"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-exporter-handle"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/exporters/handle"
        , description = Some "Handle-based span exporter"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-exporter-in-memory"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/exporters/in-memory"
        , description = Some "In-memory span exporter for testing"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-exporter-otlp"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/exporters/otlp"
        , description = Some "OTLP span exporter"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-otlp"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-w3c"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-cloudflare"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/cloudflare"
        , description = Some "Cloudflare instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-wai"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-conduit"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/conduit"
        , description = Some "Conduit instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-hspec"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/hspec"
        , description = Some "Hspec instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-http-client"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/http-client"
        , description = Some "HTTP client instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-conduit"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-hw-kafka-client"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/hw-kafka-client"
        , description = Some "hw-kafka-client instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-semantic-conventions"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-persistent"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/persistent"
        , description = Some "Persistent instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-persistent-mysql"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/persistent-mysql"
        , description = Some "Persistent MySQL instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-persistent"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-postgresql-simple"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/postgresql-simple"
        , description = Some "postgresql-simple instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-tasty"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/tasty"
        , description = Some "Tasty test framework instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-sdk"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-wai"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/wai"
        , description = Some "WAI middleware instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-instrumentation-yesod"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/yesod"
        , description = Some "Yesod instrumentation"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-wai"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-propagator-b3"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/propagators/b3"
        , description = Some "B3 context propagator"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-propagator-datadog"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/propagators/datadog"
        , description = Some "Datadog context propagator"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-propagator-w3c"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/propagators/w3c"
        , description = Some "W3C TraceContext and Baggage propagator"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-utils-exceptions"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/utils/exceptions"
        , description = Some "Exception handling utilities for OpenTelemetry"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-sdk"
          ]
        }
      , Schema.Package::{ name = "hs-opentelemetry-vendor-honeycomb"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/vendors/honeycomb"
        , description = Some "Honeycomb vendor integration"
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        }
      ]
    , docs =
      [ Schema.DocRef::{ key = "api-sdk-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "OpenTelemetry API and SDK overview"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-API-SDK-Guide.md"
        }
      , Schema.DocRef::{ key = "batch-processor-filtering-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Batch processor filtering configuration"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-BatchProcessor-Filtering-Guide.md"
        }
      , Schema.DocRef::{ key = "context-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "OpenTelemetry context propagation"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Context-Guide.md"
        }
      , Schema.DocRef::{ key = "custom-sampler-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Building custom samplers"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Custom-Sampler-Guide.md"
        }
      , Schema.DocRef::{ key = "effectful-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Using OpenTelemetry with Effectful"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Effectful-Guide.md"
        }
      , Schema.DocRef::{ key = "exporters-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Configuring and using span exporters"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Exporters-Guide.md"
        }
      , Schema.DocRef::{ key = "immutable-span-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Working with ImmutableSpan"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-ImmutableSpan-Guide.md"
        }
      , Schema.DocRef::{ key = "in-span-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Using inSpan for tracing"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-inSpan-Guide.md"
        }
      , Schema.DocRef::{ key = "instrumentation-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Instrumentation patterns and usage"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Instrumentation-Guide.md"
        }
      , Schema.DocRef::{ key = "propagators-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Context propagators (W3C, B3, Datadog)"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Propagators-Guide.md"
        }
      , Schema.DocRef::{ key = "tracer-provider-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "TracerProvider setup and configuration"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-TracerProvider-Guide.md"
        }
      ]
    }
