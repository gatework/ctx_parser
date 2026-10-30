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
    type.const_set(:DECLARATIONS, CtxParser::Commands.new([ { dimensions: [ :inventory ], command: "show inventory", parser: parser } ]))
    type.const_set(:MODEL_PARSERS, { " C9300 " => { "show inventory" => variant } })

    expect(type.new(model: "C9300").parser_for(:inventory)).to equal(variant)
  end

  it "rejects ambiguous normalized model identities even when that model is not selected" do
    type = Class.new(CtxParser::Profile)
    type.const_set(:MODEL_PARSERS, { "C9300" => {}, " c9300 " => {} })

    expect { type.new }.to raise_error(ArgumentError)
  end

  it "rejects a registered profile without a Commands declaration before any execution" do
    type = Class.new(CtxParser::Profile)
    type.const_set(:DECLARATIONS, { inventory: "show inventory" })

    expect { CtxParser::Registry.new(profiles: { platform: type }) }.to raise_error(ArgumentError)
  end

  it "rejects invalid unused model overrides while registering the profile" do
    [ { "C9300" => {}, " c9300 " => {} }, { "C9300" => { "missing command" => Object } } ].each do |models|
      type = Class.new(CtxParser::Profile)
      type.const_set(:MODEL_PARSERS, models)
      expect { CtxParser::Registry.new(profiles: { platform: type }) }.to raise_error(ArgumentError)
    end
  end

  it "keeps existing instances bound to their original static declaration" do
    type = Class.new(CtxParser::Profile)
    first = CtxParser::Commands.new([ { dimensions: [ :inventory ], command: "show first", parser: parser } ])
    second = CtxParser::Commands.new([ { dimensions: [ :inventory ], command: "show second", parser: parser } ])
    type.const_set(:DECLARATIONS, first)
    original = type.new
    type.send(:remove_const, :DECLARATIONS)
    type.const_set(:DECLARATIONS, second)

    expect(original.command(:inventory)).to eq("show first")
    expect(type.new.command(:inventory)).to eq("show second")
  end

  it "shares frozen queries across profiles and rejects an undeclared explicit command" do
    entries = 128.times.map { |index| { dimensions: [ :inventory ], command: "show port #{index}", parser: parser } }
    catalog = CtxParser::Commands.new(entries, multi_command: true)
    first = CtxParser::Profile.new(declarations: catalog)
    second = CtxParser::Profile.new(declarations: catalog).freeze
    expect(second.commands_for(:inventory)).to equal(first.commands_for(:inventory))
    entries.each { |entry| expect(second.parser_for(:inventory, command: entry[:command])).to equal(parser) }
    expect { second.parser_for(:inventory, command: "show absent") }.to raise_error(ArgumentError)
  end

  it "rejects malformed replacement declarations even for an unselected dimension" do
    entries = [ { dimensions: [ :inventory ], command: "show inventory", parser: parser },
      { dimensions: [ :other ], command: "bad\ncommand", parser: parser } ]
    expect { CtxParser::Commands.new(entries) }.to raise_error(ArgumentError)
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
