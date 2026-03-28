let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/8415b4b8a746a84eecf982f0f1d7194368bf7b54/package.dhall
        sha256:d19ae156d6c357d982a1aea0f1b6ba1f01d76d2d848545b150db75ed4c39a8a9

in  { project =
        { name = "hs-opentelemetry"
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
      [ { name = "hs-opentelemetry"
        , github = Some "iand675/hs-opentelemetry"
        , gitlab = None Text
        , git = None Text
        , localPath = Some "hs-opentelemetry"
        }
      ]
    , packages =
      [ { name = "hs-opentelemetry-api"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/api"
        , description = Some "OpenTelemetry API for Haskell"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies = [] : List Schema.Dependency
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-sdk"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/sdk"
        , description = Some "OpenTelemetry SDK for Haskell"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-exporter-otlp"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-b3"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-datadog"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-w3c"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-otlp"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/otlp"
        , description = Some "OTLP protocol types for Haskell"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies = [] : List Schema.Dependency
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-semantic-conventions"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/semantic-conventions"
        , description = Some "OpenTelemetry semantic conventions"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-exporter-handle"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/exporters/handle"
        , description = Some "Handle-based span exporter"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-exporter-in-memory"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/exporters/in-memory"
        , description = Some "In-memory span exporter for testing"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-exporter-otlp"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/exporters/otlp"
        , description = Some "OTLP span exporter"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-otlp"
          , Schema.Dependency.ByName "hs-opentelemetry-propagator-w3c"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-cloudflare"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/cloudflare"
        , description = Some "Cloudflare instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-wai"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-conduit"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/conduit"
        , description = Some "Conduit instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-hspec"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/hspec"
        , description = Some "Hspec instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-http-client"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/http-client"
        , description = Some "HTTP client instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-conduit"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-hw-kafka-client"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/hw-kafka-client"
        , description = Some "hw-kafka-client instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-semantic-conventions"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-persistent"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/persistent"
        , description = Some "Persistent instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-persistent-mysql"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/persistent-mysql"
        , description = Some "Persistent MySQL instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-persistent"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-postgresql-simple"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/postgresql-simple"
        , description = Some "postgresql-simple instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-tasty"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/tasty"
        , description = Some "Tasty test framework instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-sdk"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-wai"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/wai"
        , description = Some "WAI middleware instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-instrumentation-yesod"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/instrumentation/yesod"
        , description = Some "Yesod instrumentation"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-instrumentation-wai"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-propagator-b3"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/propagators/b3"
        , description = Some "B3 context propagator"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-propagator-datadog"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/propagators/datadog"
        , description = Some "Datadog context propagator"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-propagator-w3c"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/propagators/w3c"
        , description = Some "W3C TraceContext and Baggage propagator"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-utils-exceptions"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/utils/exceptions"
        , description = Some "Exception handling utilities for OpenTelemetry"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api"
          , Schema.Dependency.ByName "hs-opentelemetry-sdk"
          ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      , { name = "hs-opentelemetry-vendor-honeycomb"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "hs-opentelemetry/vendors/honeycomb"
        , description = Some "Honeycomb vendor integration"
        , visibility = Schema.Visibility.Public
        , lifecycle = None Schema.Lifecycle
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies =
          [ Schema.Dependency.ByName "hs-opentelemetry-api" ]
        , docs = [] : List Schema.DocRef
        , config = [] : List Schema.ConfigItem
        , apiSource = None Schema.ApiSource
        }
      ]
    , bundles = [] : List Schema.PackageBundle
    , dependencies = [] : List Text
    , apis = [] : List Schema.Api
    , agents = [] : List Schema.AgentHint
    , skills = [] : List Schema.Skill
    , subagents = [] : List Schema.Subagent
    , standards = [] : List Text
    , docs =
      [ { key = "api-sdk-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "OpenTelemetry API and SDK overview"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-API-SDK-Guide.md"
        }
      , { key = "batch-processor-filtering-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Batch processor filtering configuration"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-BatchProcessor-Filtering-Guide.md"
        }
      , { key = "context-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "OpenTelemetry context propagation"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Context-Guide.md"
        }
      , { key = "custom-sampler-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Building custom samplers"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Custom-Sampler-Guide.md"
        }
      , { key = "effectful-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Using OpenTelemetry with Effectful"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Effectful-Guide.md"
        }
      , { key = "exporters-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Configuring and using span exporters"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Exporters-Guide.md"
        }
      , { key = "immutable-span-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Working with ImmutableSpan"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-ImmutableSpan-Guide.md"
        }
      , { key = "in-span-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Using inSpan for tracing"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-inSpan-Guide.md"
        }
      , { key = "instrumentation-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Instrumentation patterns and usage"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Instrumentation-Guide.md"
        }
      , { key = "propagators-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Context propagators (W3C, B3, Datadog)"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-Propagators-Guide.md"
        }
      , { key = "tracer-provider-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "TracerProvider setup and configuration"
        , location = Schema.DocLocation.LocalFile "docs/OpenTelemetry-TracerProvider-Guide.md"
        }
      ]
    }
