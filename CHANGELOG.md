# Changelog

Changes to the public contract are recorded here. Versions follow Semantic Versioning.

## Unreleased

## 0.2.5 (2026-10-19)

- Keep offline example facts and configuration benchmark inputs independent of Ruby's global input and output separators.
- Reuse validated dynamic command directories and membership indexes when their complete contents are frozen, avoiding repeated full-directory validation during discovered-query preparation. Mutable and replaced directories retain current lookup semantics.

## 0.2.4 (2026-10-18)

- Clear Bundler bootstrap variables when verifying packages in an isolated gem installation, including calls made through bundle exec.

- Reduce temporary grouping allocations in Records while preserving callback counts, identity equality, record ownership and selection order.

## 0.2.3 (2026-10-18)

- Redact Result, Results and Line during pretty printing, including nested containers.
- Normalize model override names, reject normalized collisions, and validate static registry command/parser consistency.
- Report missing dynamic parser implementations as argument errors; retain dynamic command lookup.
- Accept signed decimal integers when bounds permit negative values, and detach host-bit-preserving prefix results from caller strings.
- Add optional byte budgets to Cursor and Document, load Banner from the root, and remove the source-type circular require.
- Reuse validated deeply frozen plain containers and frozen source strings while preserving cycle detection and defensive copies for mutable values.
- Require ipaddr 1.2.3 or newer for strict address parsing; retain the Ruby 4.0.6 support policy.

## 0.2.2 (2026-10-18)

- Preserve exact block, capture and unresolved source text independently of Ruby's global output separator.
- Normalize source lines independently of Ruby's global input separator, without an intermediate chomp allocation.
- Build cursor lines directly during scanning instead of retaining an intermediate source-line array.
- Return false from IP address validation for incompatible string encodings.

## 0.2.1 (2026-10-17)

- Update the configuration benchmark to use the Baseline 0.2 vendor parser namespace.

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
