# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "rbconfig"
require "json"

RSpec.describe "Standalone CtxParser loading" do
  it "loads each public abstraction directly without relying on the root entrypoint" do
    { "parser" => "Parser", "configuration" => "Configuration", "results" => "Results", "commands" => "Commands",
      "block" => "Block", "capture" => "Capture", "cursor" => "Cursor", "document" => "Document" }.each do |file, constant|
      script = <<~RUBY
        require "ctx_parser/#{file}"
        abort "Missing abstraction" unless CtxParser.const_defined?(#{constant.inspect}, false)
        abort "Runtime parser loaded configuration state" if #{file.inspect} == "parser" && CtxParser.const_defined?(:Document, false)
        puts CtxParser.const_get(#{constant.inspect}).name
      RUBY
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-rbundler/setup",
        "-I", File.expand_path("../lib", __dir__), "-e", script)

      expect(status).to be_success, stderr
      expect(stdout.strip).to eq("CtxParser::#{constant}")
    end
  end

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
