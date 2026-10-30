# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/profile"

RSpec.describe "Profiles with independent commands for a dimension" do
  let(:first_parser) do
    Class.new(CtxParser::Parser) do
      private

      def parse_output(text, complete:)
        result = CtxParser::Result.new(status: complete ? :complete : :partial, records: [ { source: text } ], issues: [])
        CtxParser::Results.new(by_dimension: { counters: result, interfaces: result, shared: result })
      end
    end
  end
  let(:second_parser) do
    Class.new(CtxParser::Parser) do
      private

      def parse_output(text, complete:)
        result = CtxParser::Result.new(status: complete ? :complete : :partial, records: [ { second: text } ], issues: [])
        CtxParser::Results.new(by_dimension: { counters: result, alarms: result, shared: result })
      end
    end
  end
  let(:profile_class) do
    declarations = CtxParser::Commands.new([
      { dimensions: %i[counters interfaces shared], command: "show input counters", parser: first_parser },
      { dimensions: %i[counters alarms shared], command: "show output counters", parser: second_parser }
    ], multi_command: true)
    Class.new(CtxParser::Profile).tap do |type|
      type.const_set(:DECLARATIONS, declarations)
    end
  end
  let(:profile) { profile_class.new }

  it "builds one immutable query plan in selection order for shared and multi-command views" do
    names = %i[alarms interfaces counters]
    queries = profile.queries(names)
    expect(queries).to eq("show output counters" => %i[alarms counters], "show input counters" => %i[interfaces counters])
    expect(queries.keys).to eq([ "show output counters", "show input counters" ])
    expect(names).to eq(%i[alarms interfaces counters])
    expect { queries.values.first.clear }.to raise_error(FrozenError)
    expect { queries.clear }.to raise_error(FrozenError)
    expect(profile.queries([])).to eq({})
    [ nil, %i[counters counters], [ :missing ] ].each do |selection|
      expect { profile.queries(selection) }.to raise_error(ArgumentError)
    end
  end

  it "returns immutable command arrays while preserving the single-command API" do
    expect(profile.commands_for(:counters)).to eq([ "show input counters", "show output counters" ])
    expect(profile.commands_for(:interfaces)).to eq([ "show input counters" ])
    expect(profile.command(:interfaces)).to eq("show input counters")
    expect { profile.command(:counters) }.to raise_error(ArgumentError, /multiple commands/)
    expect { profile.commands_for(:counters).pop }.to raise_error(FrozenError)
    expect { profile.commands_for(:counters).first.replace("other") }.to raise_error(FrozenError)
    expect { profile.commands_for(:missing) }.to raise_error(ArgumentError, "Unsupported parser dimension")
  end

  it "selects an exact query and parses only its own body once" do
    expect(second_parser).to receive(:parse).with("output body", complete: true).once.and_call_original
    expect(first_parser).not_to receive(:parse)
    result = profile.parse_many(%i[counters alarms], "output body", complete: true, command: "show output counters")
    expect(result.keys).to eq(%i[counters alarms])
    expect(result.values).to all(be_complete)
    expect(result[:counters].records).to eq([ { second: "output body" } ])
    expect(profile.parser_for(:counters, command: "show output counters")).to equal(second_parser)
  end

  it "infers only the unique query common to every requested view" do
    result = profile.parse_many(%i[counters interfaces], "input body", complete: true)
    expect(result[:counters].records).to eq([ { source: "input body" } ])
    expect(profile.parse(:counters, "output body", command: "show output counters").records).to eq([ { second: "output body" } ])
    expect { profile.parse(:counters, "body") }.to raise_error(ArgumentError, "One CLI output must belong to one command")
    expect { profile.parse_many(%i[counters shared], "body") }.to raise_error(ArgumentError)
    expect { profile.parse_many(%i[interfaces alarms], "body") }.to raise_error(ArgumentError)
    expect { profile.parser_for(:counters) }.to raise_error(ArgumentError)
  end

  it "rejects undeclared, wrong-view and non-string selectors before parsing" do
    expect(first_parser).not_to receive(:parse)
    expect(second_parser).not_to receive(:parse)
    [ "missing", :"show input counters", false, "show input counters\nshow output counters" ].each do |command|
      expect { profile.parse_many([ :interfaces ], "body", command: command) }.to raise_error(ArgumentError)
    end
    expect { profile.parse_many(%i[counters interfaces], "body", command: "show output counters") }.to raise_error(ArgumentError)
    expect { profile.parser_for(:interfaces, command: "show output counters") }.to raise_error(ArgumentError)
    [ nil, [], %i[counters counters] ].each do |names|
      expect { profile.parse_many(names, "body", command: "show input counters") }.to raise_error(ArgumentError)
    end
  end

  it "keeps the requested views when a parser callback changes the caller selection" do
    dimensions = %i[counters interfaces]
    original = first_parser.method(:parse)
    first_parser.define_singleton_method(:parse) do |text, complete: false|
      dimensions.replace([ :alarms ])
      original.call(text, complete: complete)
    end

    result = profile.parse_many(dimensions, "input body", complete: true)

    expect(result.keys).to eq(%i[counters interfaces])
    expect(result.values).to all(be_complete)
    expect(dimensions).to eq([ :alarms ])
  end

  it "applies a model override to the selected query without changing its other query" do
    variant = Class.new(second_parser)
    overrides = { "show output counters" => variant }
    profile_class.const_set(:MODEL_PARSERS, { "fixture" => overrides })
    selected = profile_class.new(model: " FIXTURE ")
    overrides.clear

    expect(selected.parser_for(:counters, command: "show output counters")).to equal(variant)
    expect(selected.parser_for(:counters, command: "show input counters")).to equal(first_parser)
    expect(profile_class.new.parser_for(:counters, command: "show output counters")).to equal(second_parser)
    expect(selected.parse_many(%i[counters alarms], "variant", complete: true)[:alarms]).to be_complete
  end

  it "does not freeze mutable manually declared command data owned by the caller" do
    input = +"show input counters"
    declarations = [ input ]
    type = Class.new(CtxParser::Profile)
    type.const_set(:DECLARATIONS, CtxParser::Commands.new([ { dimensions: [ :counters ], command: input, parser: first_parser } ]))
    commands = type.new.commands_for(:counters)
    input.replace("caller changed")
    declarations.clear
    expect(commands).to eq([ "show input counters" ])
    expect(commands).to be_frozen
  end
end
