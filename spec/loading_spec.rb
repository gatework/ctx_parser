# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "rbconfig"
require "json"

RSpec.describe "Standalone CtxParser loading" do
  it "keeps the offline example facts independent of process source separators" do
    script = <<~'RUBY'
      $/ = nil
      $, = "separator"
      load "examples/offline.rb"
      result = ExampleStatusParser.parse("Eth1/1 up\nEth1/2 down\n", complete: true)
      expected = [{ name: "Eth1/1", state: :up }, { name: "Eth1/2", state: :down }]
      abort "Example facts changed" unless result.complete? && result.records == expected && result.issues.empty?
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", script)

    expect(status.success?).to be(true), "#{output}#{error}"
    expect(output).to eq("Parse status: complete\nEth1/1: up\nEth1/2: down\n")
  end

  it "validates standalone cursor capture sources without depending on root loading" do
    script = <<~RUBY
      require "ctx_parser/cursor"
      cursor = CtxParser::Cursor.new("root\\n")
      begin
        cursor.capture(Object.new, data: {}, path: [])
        abort "Invalid capture accepted"
      rescue ArgumentError
        abort "Capture registered on failure" unless cursor.captures.empty?
      end
    RUBY
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-w", "-I", File.expand_path("../lib", __dir__), "-e", script)
    expect(status).to be_success, stderr
    expect(stderr).not_to include("circular require")
  end

  it "allows a namespace autoloader to reenter the root while Parser itself is loading" do
    script = <<~RUBY
      autoload :CtxParser, "ctx_parser"
      require "ctx_parser/parser"
      abort "Base parser unavailable" unless CtxParser::Parser.respond_to?(:parse)
    RUBY
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script)
    expect(status).to be_success, stderr
  end

  it "provides Banner from the root entrypoint without circular loading warnings" do
    %w[ctx_parser ctx_parser/block ctx_parser/cursor ctx_parser/capture].each do |entrypoint|
      script = <<~RUBY
        require #{entrypoint.inspect}
        require "ctx_parser"
        banner = CtxParser::Banner.new
        abort "Banner unavailable" unless banner.consume("banner motd #") && banner.open?
      RUBY
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-w", "-I", File.expand_path("../lib", __dir__), "-e", script)
      expect(status).to be_success, stderr
      expect(stderr).not_to include("circular require")
    end
  end

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
