# ctx_parser

[简体中文](README-zh.md) | [Source](https://github.com/gatework/ctx_parser) | [Changelog](CHANGELOG.md)

Shared, pure Ruby building blocks for network CLI parsing. It provides immutable results, source cursors, configuration trees, command declarations, and platform profiles without owning vendor syntax or device sessions.

## Features

- `Parser` and `Configuration` define explicit text and completeness boundaries.
- `Cursor`, `Document`, and `Capture` preserve source positions and nested configuration context.
- `Profile`, `Commands`, and `Registry` select declared platform/model behavior and share parsing across views.
- `Values`, `Records`, and `Immutable` centralize conversion, identity checks, and defensive copies.

## Installation

Requires **Ruby 4.0.6 or newer**. Add this line to your application's `Gemfile`:

```ruby
gem "ctx_parser"
```

Then run `bundle install`, or install directly with `gem install ctx_parser`. The require path is `ctx_parser` and the public namespace is `CtxParser`; package names and Ruby namespaces are intentionally separate.

This package has no dependency on the other Gatework domain gems. The gemspec declares `ipaddr` and `digest` without version constraints. Select and validate the runtime dependency combination in the application lockfile. Applications should commit their own `Gemfile.lock` to make deployments reproducible. No Rails boot or sibling checkout paths are required.

Release artifacts and checksums are available from [GitHub Releases](https://github.com/gatework/ctx_parser/releases). Check [RubyGems](https://rubygems.org/gems/ctx_parser) for published versions.

## Offline example

From a development checkout after installing dependencies:

```sh
bundle exec ruby examples/offline.rb
```

The example uses synthetic data and performs no network access:

```ruby
require "ctx_parser"

# 示例仅实现小型语法；厂商语法应放入对应领域 gem。
class ExampleStatusParser < CtxParser::Parser
  private

  # 保留未知行，并遵循调用方声明的传输完整性。
  def parse_output(text, complete:)
    records = []
    issues = []
    text.each_line("\n").with_index(1) do |line, number|
      next if line.strip.empty?

      match = /\A([A-Za-z0-9\/]+) (up|down)\z/.match(line.strip)
      if match
        records << { name: match[1], state: match[2].to_sym }
      else
        issues << { code: :unrecognized_row, line: number }
      end
    end
    status = complete && issues.empty? && !records.empty? ? :complete : :partial
    CtxParser::Result.new(status: status, records: records, issues: issues)
  end
end

result = ExampleStatusParser.parse("Eth1/1 up\nEth1/2 down\n", complete: true)
puts "Parse status: #{result.status}"
result.records.each { |row| puts "#{row[:name]}: #{row[:state]}" }
```

## Public contract and limits

`Parser.parse(text, complete: false)` returns a `Result` with `status`, `records`, and `issues`; a multi-view parser can return `Results`. Result statuses are `complete`, `partial`, `failed`, and `unsupported`. Subclasses implement `parse_output`. Configuration subclasses can use `analyze` and `capture` to preserve provenance.

`complete: true` confirms that the caller received the entire input; it does not certify that all syntax was understood. Unknown rows, identity conflicts, and insufficient empty-table evidence must remain explicit. Result records and issues must be arrays of hashes. Results and completed document diagnostics own immutable snapshots. `inspect`, `to_s`, and pretty printing omit result facts and diagnostics; explicit record access still returns the original facts. Source cursors intentionally retain original input and must not be logged when it contains secrets.

This gem supplies no vendor command declarations, transport, persistence, or health policy. Parser/registry argument errors remain exceptions for callers to handle at their own boundary.

Detailed vendor behavior, historical validation notes, and Motor-only integration are preserved in [the architecture reference](docs/architecture-zh.md). Host integration examples in that reference require Motor; they are not standalone gem APIs. Motor adapters live under `backend/lib/baseline`, `backend/lib/vxlan`, and `backend/lib/wireless` in the [Motor repository](https://github.com/gatework/motor/tree/main/backend/lib).

## Domain vocabulary

Names use domain nouns: `Configuration` parses configuration documents; `Result` holds one result and `Results` holds named results; `Commands` stores command declarations. Both collections expose their dimension index as `by_dimension`. Generic `Parser` owns the text parsing contract; configuration source state belongs to `Configuration`.

A dimension is a named view of facts; a command is the CLI query that supplies those facts. `Profile#queries` groups dimensions by command, and model overrides choose parsers for commands. `Records` groups rows by logical identity; duplicate identity counts and redundant row counts are different quantities. `Line`, `Block`, and `Capture` retain source locations, while `Result` contains normalized facts and diagnostics. Neither parsing completeness nor an empty result establishes device health.

Address conversion uses `Values.ip_address`, `Values.ip_address?`, and `Values.mac_address`. `Values.ipv4_prefix(..., preserve_host_bits: true)` explicitly preserves interface host bits; its default returns a network prefix.

`Cursor.new(text, max_bytes: limit)` and `Document.new(source, max_bytes: limit)` enforce an optional input byte budget before constructing or consuming lines. For an existing cursor, the budget applies to its normalized content. Invalid encoding remains an error: known Latin-1 input can be tagged as `Encoding::ISO_8859_1` before parsing and is transcoded to UTF-8; bytes are never silently scrubbed into facts.

`MODEL_PARSERS` model names are stripped and lowercased just like the requested model. Normalization collisions and invalid overrides are rejected. `Registry` validates static command/parser declarations when registering a profile; dynamic directory lookup remains validated when used and reports missing implementations as `ArgumentError`.

Profiles reuse query lists and membership indexes for fully frozen plain command directories, including directories created by discovery. Replacing a directory rebuilds its index; mutable entries are validated on each lookup. `bundle exec ruby -Ilib benchmark/profile.rb` measures preparation of 32, 128 and 512 synthetic commands and checks selection order and rejection of unknown commands.

`Records` owns selection arrays, while row objects remain caller-owned: treat those rows as stable during use, or pass `Immutable.copy(rows)` when a snapshot is needed. `Immutable.copy` can reuse fully frozen plain trees after validating all descendants; shallow-frozen containers, custom Hash behavior, and cycles receive the existing copy or rejection behavior. Integer conversion accepts a minus sign only when `min` permits negative values (or is `nil`); the default remains nonnegative.

## Development and tests

Name shared classes by their responsibility and use the namespace for platform context. Preserve filenames and class names that directly match device commands.

```sh
bundle install
bundle exec rake
bundle exec ruby examples/offline.rb
bundle exec rake build
```

`bundle exec rake` runs RSpec, RuboCop, and the offline examples. Tests live in `spec/`, following the existing project's RSpec convention; fixtures use synthetic or sanitized evidence. Add regression cases for successful, incomplete, unsupported, and malformed inputs when extending a parser. Offline tests do not certify all device versions or replace live integration checks.

Use the declared minimum Ruby version for compatibility checks. Document source methods and non-obvious business logic in concise Chinese, preserve public return/error contracts, and never add raw device captures or credentials to examples, fixtures, logs, or release archives.

Development commands below require a source checkout; tests, benchmarks, and scripts are intentionally excluded from the installed gem archive.

Run `bundle exec ruby -Ilib benchmark/snapshots.rb` to measure repeated wrapping of frozen results, and `bundle exec ruby -Ilib benchmark/source.rb` to measure cursor and document construction with synthetic input and semantic checks. It needs no domain gems and reports elapsed time and allocated objects; these local measurements do not establish device performance.

## Release

This directory can be maintained as the independent [ctx_parser](https://github.com/gatework/ctx_parser) repository. Update `VERSION` and `CHANGELOG.md`, run the validation and build commands above, and inspect the packaged file list before tagging `vVERSION`.

CI runs tests, lint, examples, build, and an isolated installation on Linux and macOS. After CI passes on `main`, push `vVERSION` to run the release workflow. It publishes the tested Linux artifact to RubyGems and GitHub Releases, attaches `SHA256SUMS`, and verifies downloaded bytes. The GitHub `release` environment accepts a `RUBYGEMS_API_KEY` secret; without it, configure RubyGems Trusted Publishing for this repository, `release.yml`, and the `release` environment. Retry a failed publish job to reuse its CI artifact; an already published version must have identical bytes. See [release details](docs/release.md).

Publish dependency gems first. A Git tag, a successful build, or a workflow file does not establish that the gem has reached RubyGems; confirm the registry result separately. See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

MIT. See [LICENSE](LICENSE).
