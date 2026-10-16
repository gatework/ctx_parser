# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "rbconfig"
require "json"

RSpec.describe "Standalone CtxParser loading" do
  it "loads the shared abstraction without loading any concrete vendor or Rails" do
    script = <<~RUBY
      require "ctx_parser"
      abort "Unexpected vendor dependency" if defined?(Vxlan::ParserRegistry) || defined?(Wireless::ParserRegistry) || defined?(Rails)
      puts CtxParser::Profile.name
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-rbundler/setup",
      "-I", File.expand_path("../lib", __dir__), "-e", script)

    expect(status).to be_success, stderr
    expect(stdout.strip).to eq("CtxParser::Profile")
  end
end
