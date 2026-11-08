# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `vpc_access`: outbound access to a VPC through Direct VPC egress (`network`,
  `subnetwork`, `network_tags`) or a Serverless VPC Access connector
  (`connector`), with `egress` defaulting to `PRIVATE_RANGES_ONLY`. Validation
  requires exactly one of the two modes and rejects `network_tags` with a
  connector. Defaults to `null`, so existing services plan unchanged.
- `startup_probe` and `liveness_probe`: HTTP GET (`path`), gRPC
  (`grpc_service`) or TCP probes with `port`, `initial_delay_seconds`,
  `timeout_seconds`, `period_seconds` and `failure_threshold`. Timings are
  validated against the Cloud Run limits (startup delay and period up to 240 s,
  liveness up to 3600 s, timeout not above period). Both default to `null`, so
  existing services plan unchanged.

## [1.1.0] - 2026-11-05

### Added

- `deletion_protection` input on the Cloud Run service, defaulting to `true`
  as in the google provider since 6.0.

### Changed

- The google provider constraint is now `>= 6.0, < 9.0` (was `>= 5.0`). CI
  tests against 6.0.0 and the latest 8.x, adds Dependabot, and the workflow
  token is restricted to `contents: read`.

## [1.0.0]

Initial release (`v0.1.0` points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-google-cloud-run/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/moveeeax/terraform-google-cloud-run/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/moveeeax/terraform-google-cloud-run/releases/tag/v1.0.0
