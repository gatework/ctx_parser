# frozen_string_literal: true

require_relative "spec_helper"
require "pp"

RSpec.describe "Reviewed public boundaries" do
  let(:parser) do
    Class.new(CtxParser::Parser) do
      private

      def parse_output(_text, complete:)
        CtxParser::Result.new(status: complete ? :complete : :partial)
      end
    end
  end

  it "redacts Data members when pretty printed directly or inside containers" do
    secret = "PASSWORD_SENTINEL"
    result = CtxParser::Result.new(status: :partial, records: [ { password: secret } ], issues: [ { detail: secret } ])
    results = CtxParser::Results.new(by_dimension: { inventory: result })
    line = CtxParser::Line.new(index: 0, raw: secret)
    [ result, results, line ].each do |value|
      output = PP.pp(value, +"")
      expect(output).not_to include(secret)
      expect(output.strip).to eq(value.inspect)
      expect(PP.pp({ value: value }, +"")).not_to include(secret)
    end
  end

  it "selects normalized model declarations instead of silently using the default parser" do
    variant = Class.new(parser)
    type = Class.new(CtxParser::Profile)
    type.const_set(:COMMANDS, { inventory: "show inventory" })
    type.const_set(:PARSERS, { "show inventory" => parser })
    type.const_set(:MODEL_PARSERS, { " C9300 " => { "show inventory" => variant } })

    expect(type.new(model: "C9300").parser_for(:inventory)).to equal(variant)
  end

  it "rejects ambiguous normalized model identities even when that model is not selected" do
    type = Class.new(CtxParser::Profile)
    type.const_set(:MODEL_PARSERS, { "C9300" => {}, " c9300 " => {} })

    expect { type.new }.to raise_error(ArgumentError)
  end

  it "rejects a registered profile with a missing command parser before any execution" do
    type = Class.new(CtxParser::Profile)
    type.const_set(:COMMANDS, { inventory: "show inventory" })

    expect { CtxParser::Registry.new(profiles: { platform: type }) }.to raise_error(ArgumentError)
  end

  it "rejects invalid unused model overrides while registering the profile" do
    [ { "C9300" => {}, " c9300 " => {} }, { "C9300" => { "missing command" => Object } } ].each do |models|
      type = Class.new(CtxParser::Profile)
      type.const_set(:MODEL_PARSERS, models)
      expect { CtxParser::Registry.new(profiles: { platform: type }) }.to raise_error(ArgumentError)
    end
  end

  it "reports dynamic missing implementations as argument errors at lookup" do
    type = Class.new(CtxParser::Profile)
    type.const_set(:COMMANDS, { inventory: "show inventory" })
    type.const_set(:PARSERS, { "show inventory" => parser })
    profile = type.new
    type::PARSERS.clear

    expect { profile.parser_for(:inventory) }.to raise_error(ArgumentError)
  end

  it "reuses immutable validated command queries without caching replaced catalogs" do
    query = "show inventory".freeze
    directory = { inventory: [ query ].freeze }.freeze
    type = Class.new(CtxParser::Profile)
    type.const_set(:COMMANDS, directory)
    type.const_set(:PARSERS, { query => parser })
    profile = type.new
    first = profile.commands_for(:inventory)
    expect(profile.commands_for(:inventory)).to equal(first)
    type.send(:remove_const, :COMMANDS)
    type.const_set(:COMMANDS, { inventory: "show replacement" })
    type::PARSERS["show replacement"] = parser
    expect(profile.command(:inventory)).to eq("show replacement")
    expect(profile.parser_for(:inventory)).to equal(parser)
  end

  it "does not reinterpret identity-based catalogs when preparing query reuse" do
    first, second = +"inventory", +"inventory"
    directory = {}.compare_by_identity
    directory[first] = [ "show first" ].freeze
    directory[second] = [ "show second" ].freeze
    type = Class.new(CtxParser::Profile)
    type.const_set(:COMMANDS, directory.freeze)

    expect(type.new.command(first)).to eq("show first")
    expect(type.new.command(second)).to eq("show second")
  end

  it "reuses expanded frozen queries when validating every discovered command", :aggregate_failures do
    queries = 128.times.map { |index| "show port #{index}".freeze }.freeze
    type = Class.new(CtxParser::Profile) do
      attr_accessor :directory
      attr_reader :validated_entries

      def commands = directory

      private

      def validated_queries(declaration)
        @validated_entries = (@validated_entries || 0) + Array(declaration).size
        super
      end
    end
    type.const_set(:PARSERS, queries.to_h { |query| [ query, parser ] }.freeze)
    profile = type.new
    profile.directory = { inventory: queries }.freeze
    first = profile.commands_for(:inventory)
    queries.each { |query| expect(profile.parser_for(:inventory, command: query)).to equal(parser) }

    expect(profile.commands_for(:inventory)).to equal(first)
    expect(profile.validated_entries).to eq(queries.size)
    expect { profile.parser_for(:inventory, command: "show absent") }.to raise_error(ArgumentError)
  end

  it "refreshes a duplicated profile after its frozen discovery directory is replaced" do
    type = Class.new(CtxParser::Profile) { attr_accessor :directory; def commands = directory }
    type.const_set(:PARSERS, { "show first" => parser, "show second" => parser })
    original = type.new
    original.directory = { inventory: [ "show first" ].freeze }.freeze
    expect(original.command(:inventory)).to eq("show first")
    expanded = original.dup
    expanded.directory = { inventory: [ "show second" ].freeze }.freeze

    expect(expanded.parser_for(:inventory, command: "show second")).to equal(parser)
    expect { expanded.parser_for(:inventory, command: "show first") }.to raise_error(ArgumentError)
    expect(original.command(:inventory)).to eq("show first")
  end

  it "continues validating mutable children of a frozen dynamic directory" do
    type = Class.new(CtxParser::Profile) { attr_accessor :directory; def commands = directory }
    type.const_set(:PARSERS, { "show first" => parser, "show second" => parser })
    profile = type.new
    query = +"show first"
    profile.directory = { inventory: [ query ].freeze }.freeze
    expect(profile.command(:inventory)).to eq("show first")
    query.replace("show second")
    expect(profile.parser_for(:inventory, command: "show second")).to equal(parser)
    expect { profile.parser_for(:inventory, command: "show first") }.to raise_error(ArgumentError)
    query.replace("show invalid\nreload")
    expect { profile.command(:inventory) }.to raise_error(ArgumentError)

    queries = [ "show first" ]
    profile.directory = { inventory: queries }.freeze
    expect(profile.command(:inventory)).to eq("show first")
    queries.replace([ "show second" ])
    expect(profile.command(:inventory)).to eq("show second")
  end

  it "keeps frozen profiles readable without populating a new dynamic cache" do
    type = Class.new(CtxParser::Profile) { attr_accessor :directory; def commands = directory }
    type.const_set(:PARSERS, { "show inventory" => parser })
    profile = type.new
    profile.directory = { inventory: [ "show inventory" ].freeze }.freeze
    profile.freeze

    expect(profile.parser_for(:inventory)).to equal(parser)
  end

  it "validates an unused malformed dynamic declaration only when requested" do
    type = Class.new(CtxParser::Profile) { attr_accessor :directory; def commands = directory }
    type.const_set(:PARSERS, { "show inventory" => parser })
    profile = type.new
    profile.directory = { inventory: "show inventory", other: [ "bad\ncommand" ].freeze }.freeze

    expect(profile.parser_for(:inventory)).to equal(parser)
    expect { profile.command(:other) }.to raise_error(ArgumentError)
  end

  it "supports signed decimal values within explicitly permitted negative bounds" do
    expect(CtxParser::Values.integer(-5, min: -10)).to eq(-5)
    expect(CtxParser::Values.integer("-5", min: -10, max: -1)).to eq(-5)
    expect { CtxParser::Values.integer("-11", min: -10) }.to raise_error(CtxParser::Values::OutOfRange)
    expect { CtxParser::Values.integer("-5") }.to raise_error(ArgumentError)
    expect { CtxParser::Values.integer("+5", min: -10) }.to raise_error(ArgumentError)
  end

  it "returns an independent prefix value when retaining host bits" do
    raw = +"192.0.2.129/24"
    value = CtxParser::Values.ipv4_prefix(raw, preserve_host_bits: true)
    raw.replace("changed")

    expect(value).to eq("192.0.2.129/24")
  end
end

RSpec.describe "Source input limits" do
  it "enforces raw byte limits before cursor construction or document consumption" do
    expect(CtxParser::Cursor.new("无线", max_bytes: 6).content).to eq("无线")
    expect { CtxParser::Cursor.new("无线", max_bytes: 5) }.to raise_error(ArgumentError, /byte limit/)
    expect { CtxParser::Document.new("root\n", max_bytes: 4) }.to raise_error(ArgumentError, /byte limit/)
    cursor = CtxParser::Cursor.new("root\n")
    expect { CtxParser::Document.new(cursor, max_bytes: 4) }.to raise_error(ArgumentError, /byte limit/)
    expect(cursor.position).to eq(0)
    expect(CtxParser::Document.new(cursor, max_bytes: 5).roots.first.text).to eq("root")
    expect { CtxParser::Document.new("", max_bytes: -1) }.to raise_error(ArgumentError)
  end
end
