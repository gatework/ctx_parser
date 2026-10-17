# Changelog

Changes to the public contract are recorded here. Versions follow Semantic Versioning.

## 0.2.0 (2026-10-17)

- Validate integer inputs and bound types without implicit object conversion; reject mixed MAC separators.
- Strip hash defaults from result dimension maps and reject non-hash registry declarations at the public boundary.
- Append owned command indexes in place during construction and avoid reselecting an already validated command during profile parsing.

- Keep result interpolation redacted and reject malformed diagnostic collections.
- Detach nested document diagnostics and reject custom mutable numeric values in fact snapshots, including Complex components.
- Validate child block ownership, containment, and source order before accepting a source tree.
- Short-circuit block completeness queries without allocating line and state arrays; retain live cursor semantics.

- Reject unnamed or non-symbol result dimensions before profile selection.

- Use `Configuration`, `Results`, and `Commands` consistently; keep configuration source state in `Configuration` and name dimension indexes `by_dimension`.

- Require a boolean `allow_zone` option so string values cannot enable scoped IPv6 addresses.

- Reject nontext address identities and nonboolean host-bit preservation policies at the scalar boundary.

- Rename domain APIs directly; callers must use the new names (no compatibility aliases).

- Clarify dimension-to-command planning, model parser overrides, and record identity grouping names.

- Copy shared fact containers once, reject cyclic values with `ArgumentError`, and support deeply nested snapshots without exhausting the Ruby call stack.
- Preserve valid UTF-16/32 source encodings while checking logical NUL characters and normalizing requested line endings.

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
