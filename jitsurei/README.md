# jitsurei — practical examples

実例 — hand-maintained, runnable examples and configs that support the
`hs-opentelemetry` work but live **outside** the `hs-opentelemetry/` subtree.

Keeping them here means `git subtree pull` of upstream never conflicts with
our own material. Anything under `hs-opentelemetry/` is upstream-owned and gets
overwritten on the next sync; anything here is ours.

## Contents

- **`tail-sampling/`** — OpenTelemetry Collector config that does tail sampling
  (keep-all-errors + slow + probabilistic baseline) in front of Jaeger and/or
  VictoriaTraces. The SDK has no tail sampling by design (head sampling only,
  per the OTel spec); tail sampling belongs in the Collector. See
  [`tail-sampling/collector-config.yaml`](tail-sampling/collector-config.yaml).

  Pairs with the demo app in `hs-opentelemetry/examples/otlp-demo/`. Point the
  demo's collector at this file by mounting it as the collector config, e.g. in
  `docker-compose.yml`:

  ```yaml
  volumes:
    - ../../../jitsurei/tail-sampling/collector-config.yaml:/etc/otel/config.yaml:ro
  ```

  and keep the SDK at `always_on` / `parentbased_always_on` so the collector
  receives complete traces to sample.
