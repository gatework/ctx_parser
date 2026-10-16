# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Immutable facts and evidence" do
  it "reuses immutable strings while detaching mutable children of shallow-frozen containers" do
    label = "leaf".freeze
    caller_text = +"Ethernet1/1"
    input = { label: label, interfaces: [ caller_text ].freeze }.freeze
    value = CtxParser::Immutable.copy(input)
    caller_text.clear

    expect(value[:label]).to equal(label)
    expect(value[:interfaces]).to eq([ "Ethernet1/1" ])
    expect(value).not_to equal(input)
    expect { value[:interfaces].first.clear }.to raise_error(FrozenError)
  end

  [ CtxParser::Result ].each do |type|
    context type.name do
      let(:attributes) { type == CtxParser::Result ? {} : { name: :configuration } }

      it "detaches nested facts and diagnostics without freezing caller data" do
        records = [ { name: +"leaf", nested: { members: [ +"Ethernet1/1" ] } } ]
        issues = [ { code: :partial_source, fields: [ +"name" ] } ]
        value = type.new(**attributes, status: :partial, records: records, issues: issues)
        records.first[:name].replace("caller changed")
        records.first[:nested][:members].clear
        issues.first[:fields].clear

        expect(value.records).to eq([ { name: "leaf", nested: { members: [ "Ethernet1/1" ] } } ])
        expect(value.issues).to eq([ { code: :partial_source, fields: [ "name" ] } ])
        expect { value.records.first[:nested][:members].clear }.to raise_error(FrozenError)
        expect { value.issues.first[:fields].first.replace("changed") }.to raise_error(FrozenError)
      end

      it "keeps replacement facts independent while preserving Data value semantics" do
        original = type.new(**attributes, status: :complete, records: [ { name: "leaf" } ])
        input = [ { name: +"replacement" } ]
        replaced = original.with(status: :partial, records: input)
        input.first[:name].clear
        expect(replaced.records).to eq([ { name: "replacement" } ])
        expect(original.records).to eq([ { name: "leaf" } ])
        expect(replaced.to_h[:status]).to eq(:partial)
      end
    end
  end
end
