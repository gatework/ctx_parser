# ctx_parser

[简体中文](README-zh.md) | [Source](https://github.com/gatework/ctx_parser) | [Changelog](CHANGELOG.md)

Shared, pure Ruby building blocks for network CLI parsing. It provides immutable results, source cursors, configuration trees, command catalogs, and platform profiles without owning vendor syntax or device sessions.

## Features

- `Parser` and `ConfigurationParser` define explicit text and completeness boundaries.
- `Cursor`, `Document`, and `Capture` preserve source positions and nested configuration context.
- `Profile`, `CommandCatalog`, and `Registry` select declared platform/model behavior and share parsing across views.
- `Values`, `Records`, and `Immutable` centralize conversion, identity checks, and defensive copies.

## Installation

Requires **Ruby 4.0.6 or newer**. Add this line to your application's `Gemfile`:

```ruby
gem "ctx_parser"
```

Then run `bundle install`, or install directly with `gem install ctx_parser`. The require path is `ctx_parser` and the public namespace is `CtxParser`; package names and Ruby namespaces are intentionally separate.

This package has no dependency on the other Gatework domain gems. The gemspec declares runtime dependencies without version constraints. Applications should commit their own `Gemfile.lock` to make deployments reproducible. No Rails boot or sibling checkout paths are required.

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
    text.each_line.with_index(1) do |line, number|
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

`Parser.parse(text, complete: false)` returns a `Result` with `status`, `records`, and `issues`; a multi-view parser can return `ResultSet`. Result statuses are `complete`, `partial`, `failed`, and `unsupported`. Subclasses implement `parse_output`. Configuration subclasses can use `analyze` and `capture` to preserve provenance.

`complete: true` confirms that the caller received the entire input; it does not certify that all syntax was understood. Unknown rows, identity conflicts, and insufficient empty-table evidence must remain explicit. Results are immutable. Source cursors intentionally retain original input and must not be logged when it contains secrets.

This gem supplies no vendor command catalog, transport, persistence, or health policy. Parser/registry argument errors remain exceptions for callers to handle at their own boundary.

Detailed vendor behavior, historical validation notes, and Motor-only integration are preserved in [the architecture reference](docs/architecture-zh.md). Host integration examples in that reference require Motor; they are not standalone gem APIs. Motor adapters live under `backend/lib/baseline`, `backend/lib/vxlan`, and `backend/lib/wireless` in the [Motor repository](https://github.com/gatework/motor/tree/main/backend/lib).

## Development and tests

```sh
bundle install
bundle exec rake
bundle exec ruby examples/offline.rb
bundle exec rake build
```

`bundle exec rake` runs RSpec, RuboCop, and the offline examples. Tests live in `spec/`, following the existing project's RSpec convention; fixtures use synthetic or sanitized evidence. Add regression cases for successful, incomplete, unsupported, and malformed inputs when extending a parser. Offline tests do not certify all device versions or replace live integration checks.

Use the declared minimum Ruby version for compatibility checks. Document source methods and non-obvious business logic in concise Chinese, preserve public return/error contracts, and never add raw device captures or credentials to examples, fixtures, logs, or release archives.

## Release

This directory can be maintained as the independent [ctx_parser](https://github.com/gatework/ctx_parser) repository. Update `VERSION` and `CHANGELOG.md`, run the validation and build commands above, and inspect the packaged file list before tagging `vVERSION`.

CI runs tests, lint, examples, build, and an isolated installation on Linux and macOS. After CI passes on `main`, push `vVERSION` to run the release workflow. It publishes the tested Linux artifact to RubyGems and GitHub Releases, attaches `SHA256SUMS`, and verifies downloaded bytes. The GitHub `release` environment accepts a `RUBYGEMS_API_KEY` secret; without it, configure RubyGems Trusted Publishing for this repository, `release.yml`, and the `release` environment. Retry a failed publish job to reuse its CI artifact; an already published version must have identical bytes. See [release details](docs/release.md).

Publish dependency gems first. A Git tag, a successful build, or a workflow file does not establish that the gem has reached RubyGems; confirm the registry result separately. See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

MIT. See [LICENSE](LICENSE).
