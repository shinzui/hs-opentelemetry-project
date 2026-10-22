let UpstreamIssues =
      https://raw.githubusercontent.com/shinzui/mori-schema/b85081a0e935a976202fd7a1227f8b93e2cbeb23/extensions/upstream-issues/package.dhall
        sha256:50f8b061a1bd999aac83e3f0ed69cd5a829d2bcf101f556a733f52ed9671e064

in  UpstreamIssues.UpstreamIssuesCatalog::{
    , entries =
      [ UpstreamIssues.UpstreamIssue::{
        , key = "sdk-cumulative-observable-counters-accumulate-across-collections"
        , dependency = "hs-opentelemetry-sdk"
        , summary =
            "SDK 1.0.0.0 adds each absolute observable-counter observation to prior cumulative storage. A callback observing 7 yields 7, 14, 21 across three collectResourceMetrics calls, while a synchronous counter incremented once correctly stays 1. This affects all Int64/Double observable counters and up/down counters, inflating GHC/process metrics whenever scraping or periodic export collects them."
        , status = UpstreamIssues.IssueStatus.Workaround
        , revisitTrigger = Some
            "Adopt a published SDK/shared cohort release only after the cumulative-observation regressions pass, then remove both consumer source overrides and its vendor tree together. Hackage and upstream release tags were verified on 2026-10-22: SDK 1.0.0.0 remains the latest published release. Mechanism: hs-opentelemetry/sdk/src/OpenTelemetry/MeterProvider.hs mkObsCounterI64/mkObsCounterDbl/mkObsUDCI64/mkObsUDCDbl reuse additive sum cells; cumulative collectResourceMetrics runs callbacks without resetting asynchronous observations. A constant callback therefore accumulates across reads. The correction serializes the complete reset/callback/snapshot collection with a per-provider MVar and atomically removes only cumulative KindAsyncCounter, KindAsyncUpDownCounter and KindAsyncGauge cells plus their seriesCountByDims entries before callbacks. Synchronous cells and cardinality accounting are retained atomically with concurrent recording; delta behavior is unchanged. Callbacks must not recursively collect or force-flush their own provider. Consumer mori://tan/notification-hub implements the bounded exception in mori://tan/notification-hub/plans/107-expose-a-prometheus-metrics-endpoint-for-fleet-scraping. Its project-relative vendor/hs-opentelemetry-sdk/LOCAL-CHANGES.md records the released archive URL, SHA-256 e4e5040fd2366542feb7d0148c09e1a65a282486a542bb5ceba3b41fda5dae61, release tag hs-opentelemetry-sdk-1.0.0.0 peeling to 46a42cdf80405fdb36fbb48a309254b2332617b4, and applied cumulative-observations.patch (source-file artifact URIs pending). Cabal and Nix select the identical source. The full SDK suite passes: 196 examples, zero failures, one upstream pending. New cases cover all four observable sum types, repeated/changing/falling values, disappearing gauge labels, cardinality/overflow capacity, overlapping collections and concurrent synchronous increments/histograms, callback exceptions and cancellation recovery. The application's consumer regression also verifies stable observations. Reproduce with the plan's standalone probe in the consumer Nix shell: before 7/14/21, after 7/7/7; synchronous totals remain 1/1/1. Do not substitute delta temporality or merely serialize unmodified collections: neither fixes the single cumulative-provider scrape/push contract. No upstream GitHub ticket has been filed."
        , workaroundPath = Some "mori://tan/notification-hub (project-relative vendor/hs-opentelemetry-sdk/cumulative-observations.patch; artifact URI pending)"
        , upstreamUrl = Some "https://github.com/iand675/hs-opentelemetry"
        , tags =
          [ "metrics"
          , "cumulative-temporality"
          , "observable-counters"
          , "concurrent-collection"
          , "cardinality"
          , "vendored-workaround"
          , "no-upstream-ticket"
          ]
        }
      ]
    }
