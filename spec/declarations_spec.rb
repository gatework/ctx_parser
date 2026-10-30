# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Profile declaration snapshots" do
  let(:parser) do
    Class.new(CtxParser::Parser) do
      def parse_output(text, complete:)
        CtxParser::Result.new(status: complete ? :complete : :partial, records: [ { text: text } ])
      end
    end
  end
  let(:declarations) do
    CtxParser::Commands.new([ { dimensions: %i[inventory counters], command: "show inventory", parser: parser } ])
  end

  it "shares a validated catalog between profiles without sharing replacement state" do
    original = CtxParser::Profile.new(model: " FIXTURE ", declarations: declarations)
    replacement = CtxParser::Commands.new([ { dimensions: [ :inventory ], command: "show other", parser: parser } ])
    expanded = original.freeze.with_declarations(replacement)

    expect(expanded.declarations).to equal(replacement)
    expect(expanded.model).to eq("fixture")
    expect(expanded.command(:inventory)).to eq("show other")
    expect(original.declarations).to equal(declarations)
    expect(original.command(:inventory)).to eq("show inventory")
    expect { original.with_declarations({}) }.to raise_error(ArgumentError)
    expect(original.command(:inventory)).to eq("show inventory")
  end

  it "keeps a normalized model override when replacing declarations" do
    variant = Class.new(parser)
    type = Class.new(CtxParser::Profile)
    type.const_set(:DECLARATIONS, declarations)
    type.const_set(:MODEL_PARSERS, { " FIXTURE " => { "show inventory" => variant } })
    original = type.new(model: "fixture")
    type::MODEL_PARSERS.clear
    expanded = original.with_declarations(CtxParser::Commands.new(declarations.entries + [
      { dimensions: [ :alarms ], command: "show alarms", parser: parser }
    ]))

    expect(expanded.parser_for(:inventory)).to equal(variant)
    expect(expanded.parser_for(:alarms)).to equal(parser)
    expect(original.commands).not_to have_key(:alarms)
    empty = CtxParser::Commands.new([])
    expect { original.with_declarations(empty) }.to raise_error(ArgumentError)
    expect(original.parser_for(:inventory)).to equal(variant)
  end

  it "selects from one catalog even when an extension changes its directory on each read" do
    replacement = CtxParser::Commands.new([ { dimensions: %i[inventory counters], command: "show other", parser: parser } ])
    catalogs = [ declarations, replacement ]
    type = Class.new(CtxParser::Profile) do
      define_method(:declarations) { catalogs.rotate!.first }
    end
    profile = type.new

    expect(profile.queries(%i[inventory counters]).values).to eq([ %i[inventory counters] ])
    expect(profile.parse_many(%i[inventory counters], "body", complete: true).values).to all(be_complete)
  end

  it "does not consult independently overridden command or parser mappings" do
    type = Class.new(CtxParser::Profile) do
      def commands = raise("independent directory")
      def parsers = raise("independent implementation")
    end
    profile = type.new(declarations: declarations)
    expect(profile.parser_for(:inventory, command: +"show inventory")).to equal(parser)
    expect(profile.queries([ :inventory ])).to eq("show inventory" => [ :inventory ])
  end

  it "preserves the request when the parser changes the caller selection and command" do
    dimensions = %i[inventory counters]
    command = +"show inventory"
    implementation = parser
    implementation.define_singleton_method(:parse) do |_text, complete:|
      dimensions.clear
      command.replace("changed")
      CtxParser::Result.new(status: complete ? :complete : :partial)
    end
    result = CtxParser::Profile.new(declarations: declarations).parse_many(dimensions, "body", complete: true, command: command)
    expect(result.keys).to eq(%i[inventory counters])
    expect(result.values).to all(be_complete)
    expect(declarations.commands_for(:inventory)).to eq([ "show inventory" ])
  end

  it "rejects legacy declarations with a migration error instead of treating them as empty" do
    type = Class.new(CtxParser::Profile)
    type.const_set(:COMMANDS, { inventory: "show inventory" })
    type.const_set(:PARSERS, { "show inventory" => parser })
    expect { type.new }.to raise_error(ArgumentError, /DECLARATIONS/)
    expect { CtxParser::Registry.new(profiles: { fixture: type }) }.to raise_error(ArgumentError, /DECLARATIONS/)
  end

  it "does not mistake host constants for inherited profile declarations" do
    stub_const("COMMANDS", :host_commands)
    stub_const("PARSERS", :host_parsers)
    type = Class.new(CtxParser::Profile)
    type.const_set(:DECLARATIONS, declarations)
    expect(CtxParser::Registry.new(profiles: { fixture: type }).fetch(:fixture).command(:inventory)).to eq("show inventory")
  end
end
