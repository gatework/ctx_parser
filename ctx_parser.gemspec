# frozen_string_literal: true

require_relative "lib/ctx_parser/version"

Gem::Specification.new do |spec|
  spec.name = "ctx_parser"
  spec.version = CtxParser::VERSION
  spec.authors = [ "Gatework contributors" ]
  spec.summary = "Parse network CLI evidence into normalized facts."
  spec.description = "Reusable configuration documents, command declarations, platform profiles, immutable results and parsing primitives for network automation."
  spec.homepage = "https://github.com/gatework/ctx_parser"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.6"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}#readme",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }
  # 显式限定打包文件，排除设备回显、凭据、测试夹具和构建产物。
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "examples/**/*.rb", "docs/**/*.md", "README*.md", "CHANGELOG.md", "LICENSE"].sort }
  spec.require_paths = [ "lib" ]

  spec.add_dependency "date"
  spec.add_dependency "time"
  spec.add_dependency "digest"
  spec.add_dependency "ipaddr"
end
