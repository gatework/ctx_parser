# Changelog

Changes to the public contract are recorded here. Versions follow Semantic Versioning.

## 0.1.1 (2026-10-16)

- Publish verified artifacts using either an environment API key or RubyGems Trusted Publishing.
- The v0.1.0 tag did not reach RubyGems because credential setup failed.

## 0.1.0 (2026-10-16, unpublished)

### Added

- Shared parser contracts, configuration provenance, immutable values, and platform registries.
- Standalone RubyGems packaging under `ctx_parser` with the `ctx_parser` require path and `CtxParser` namespace.
- English and Chinese documentation, an offline example, and standalone RSpec/RuboCop development tasks.
- Linux/macOS CI, isolated package verification, and automatic RubyGems and GitHub Releases with identical artifacts.

### Changed

- Cross-module dependencies resolve through RubyGems/Bundler instead of relative sibling paths.
- Motor persistence and application-specific adapters remain in the host application.
