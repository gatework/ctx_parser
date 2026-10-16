# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/command_catalog"

RSpec.describe CtxParser::CommandCatalog do
  let(:parser) { Class.new(CtxParser::Parser) }
  let(:entry) { { dimensions: %i[access_points radios], command: +"display ap verbose", parser: parser } }

  it "indexes multiple views of one command without taking ownership of the caller's declaration" do
    declarations = [ entry ]
    catalog = described_class.new(declarations)
    entry[:dimensions].replace([ :clients ])
    entry[:command].replace("display clients")
    entry[:parser] = Class.new(CtxParser::Parser)
    declarations.clear

    expect(catalog.commands).to eq(access_points: "display ap verbose", radios: "display ap verbose")
    expect(catalog.parsers.fetch("display ap verbose")).to equal(parser)
    expect(catalog.entries.first).to eq(dimensions: %i[access_points radios], command: "display ap verbose", parser: parser)
    expect(parser).not_to be_frozen
    expect { catalog.entries << {} }.to raise_error(FrozenError)
    expect { catalog.entries.first[:dimensions] << :clients }.to raise_error(FrozenError)
    expect { catalog.entries.first[:command].replace("different") }.to raise_error(FrozenError)
    expect { catalog.entries.first[:parser] = parser }.to raise_error(FrozenError)
    expect { catalog.commands[:clients] = "display clients" }.to raise_error(FrozenError)
    expect { catalog.parsers["display clients"] = parser }.to raise_error(FrozenError)
  end

  it "rejects conflicting views and repeated commands instead of silently overwriting them" do
    duplicate_dimension = { dimensions: [ :radios ], command: "display radios", parser: parser }
    duplicate_command = { dimensions: [ :clients ], command: entry[:command], parser: parser }

    [ duplicate_dimension, duplicate_command ].each do |conflict|
      expect { described_class.new([ entry, conflict ]) }.to raise_error(ArgumentError)
    end
    expect { described_class.new([ entry.merge(dimensions: %i[radios radios]) ]) }.to raise_error(ArgumentError)
  end

  it "rejects incomplete declarations and invalid dimension identities" do
    [ nil, {}, [], [ nil ], [ entry.except(:parser) ], [ entry.merge(typo: true) ] ].each do |declarations|
      expect { described_class.new(declarations) }.to raise_error(ArgumentError)
    end
    [ nil, [], :clients, [ "clients" ], [ :"" ] ].each do |dimensions|
      expect { described_class.new([ entry.merge(dimensions: dimensions) ]) }.to raise_error(ArgumentError)
    end
  end

  it "rejects blank or multi-command text before any collection can use it" do
    [ nil, :command, "", "  ", "display ap\nreset", "display ap\rreset", "display ap\0" ].each do |command|
      expect { described_class.new([ entry.merge(command: command) ]) }.to raise_error(ArgumentError)
    end
  end

  it "requires a Parser subclass" do
    [ nil, Object, CtxParser::Parser, parser.new, -> { } ].each do |invalid|
      expect { described_class.new([ entry.merge(parser: invalid) ]) }.to raise_error(ArgumentError)
    end
  end

  it "allows explicitly enabled independent queries for a shared dimension without changing single views" do
    second = { dimensions: %i[radios clients], command: +"display radio detail", parser: parser }
    third = { dimensions: [ :radios ], command: +"display radio counters", parser: parser }
    catalog = described_class.new([ entry, second, third ], multi_command: true)
    second[:command].replace("changed")
    third[:dimensions].clear

    expect(catalog.commands).to eq(access_points: "display ap verbose",
      radios: [ "display ap verbose", "display radio detail", "display radio counters" ], clients: "display radio detail")
    expect(catalog.commands[:radios]).to be_frozen
    expect(catalog.commands[:radios]).to all(be_frozen)
    expect { catalog.commands[:radios] << "other" }.to raise_error(FrozenError)
    expect { catalog.commands[:radios].last.replace("other") }.to raise_error(FrozenError)
    expect(catalog.entries[1][:command]).to eq("display radio detail")
  end

  it "still rejects duplicate commands and dimensions within a declaration in multi-command mode" do
    duplicate = { dimensions: [ :clients ], command: entry[:command], parser: parser }
    expect { described_class.new([ entry, duplicate ], multi_command: true) }.to raise_error(ArgumentError, "Command is already declared")
    expect { described_class.new([ entry.merge(dimensions: %i[radios radios]) ], multi_command: true) }.to raise_error(ArgumentError)
    [ nil, 0, "true" ].each do |value|
      expect { described_class.new([ entry ], multi_command: value) }.to raise_error(ArgumentError)
    end
  end
end
