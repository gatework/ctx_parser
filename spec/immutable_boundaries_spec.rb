# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Immutable facts and evidence" do
  it "drops caller-owned container metadata instead of sharing its hidden mutable state" do
    [ [], {} ].each do |source|
      source.instance_variable_set(:@metadata, [])
      source.freeze
      snapshot = CtxParser::Immutable.copy(source)
      expect(snapshot.instance_variables).to be_empty
      expect(snapshot).not_to equal(source)
    end
  end

  it "reuses fully frozen plain trees after validating every nested value" do
    source = { items: [ { name: "leaf", value: 1 }.freeze ].freeze }.freeze
    expect(CtxParser::Immutable.copy(source)).to equal(source)
    expect(CtxParser::Immutable.copy([ source, source ].freeze)).to eq([ source, source ])
    cyclic = []
    cyclic << cyclic
    cyclic.freeze
    expect { CtxParser::Immutable.copy(cyclic) }.to raise_error(ArgumentError, /cyclic/)
    invalid = { items: [ Object.new.freeze ].freeze }.freeze
    expect { CtxParser::Immutable.copy(invalid) }.to raise_error(ArgumentError, /plain data/)
  end

  it "reuses validated frozen containers beyond the recursive depth limit" do
    source = "leaf".freeze
    100.times { source = [ source ].freeze }
    expect(CtxParser::Immutable.copy(source)).to equal(source)
  end

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

  it "copies shared containers once while detaching mutable caller values" do
    label = +"original"
    shared = { labels: [ label ] }
    snapshot = CtxParser::Immutable.copy([ shared, shared ])
    label.replace("changed")

    expect(snapshot.first).to equal(snapshot.last)
    expect(snapshot.first[:labels]).to eq([ "original" ])
    expect(snapshot.first).not_to equal(shared)
    expect { snapshot.first[:labels] << "new" }.to raise_error(FrozenError)
    expect(shared).not_to be_frozen
  end

  it "rejects recursive arrays and hashes as invalid plain data" do
    recursive_array = []
    recursive_array << recursive_array
    recursive_hash = {}
    recursive_hash[:self] = recursive_hash
    mixed = { child: [] }
    mixed[:child] << mixed

    [ recursive_array, recursive_hash, mixed ].each do |source|
      expect { CtxParser::Immutable.copy(source) }.to raise_error(ArgumentError, /cyclic/i)
      expect(source).not_to be_frozen
    end
  end

  it "copies deeply nested plain values without growing the Ruby call stack" do
    source = +"leaf"
    5_000.times { source = [ { nested: source } ] }
    snapshot = CtxParser::Immutable.copy(source)

    5_000.times do
      expect(snapshot).to be_frozen
      expect(snapshot.first).to be_frozen
      snapshot = snapshot.first.fetch(:nested)
    end
    expect(snapshot).to eq("leaf")
    expect(snapshot).to be_frozen
  end

  it "detects cycles that cross the bounded recursion and explicit-stack boundary" do
    root = []
    tail = root
    100.times do
      child = []
      tail << child
      tail = child
    end
    tail << root

    expect { CtxParser::Immutable.copy(root) }.to raise_error(ArgumentError, /cyclic/i)
  end

  it "copies container keys before hashing without freezing caller keys or invoking defaults" do
    key = [ +"identity" ]
    source = Hash.new { raise "default must not run" }
    source[key] = key
    snapshot = CtxParser::Immutable.copy(source)
    captured_key = snapshot.keys.first
    key.first.replace("changed")

    expect(captured_key).to eq([ "identity" ])
    expect(captured_key).to be_frozen
    expect(snapshot.fetch([ "identity" ])).to equal(captured_key)
    expect(snapshot.default_proc).to be_nil
    expect(key).not_to be_frozen
  end

  it "preserves immutable numeric values including nonfinite floating-point data" do
    values = [ Float::NAN, Float::INFINITY, -Float::INFINITY, Rational(1, 3), Complex(1, 2) ]
    snapshot = CtxParser::Immutable.copy(values)

    snapshot.zip(values).each { |copied, source| expect(copied).to equal(source) }
    expect { CtxParser::Immutable.copy([ Object.new ]) }.to raise_error(ArgumentError, /plain data/)
  end

  it "keeps ordinary hash equality and strips identity comparison and defaults" do
    source = Hash.new("fallback").compare_by_identity
    source[+"same"] = { value: "first" }
    source[+"same"] = { value: "second" }
    snapshot = CtxParser::Immutable.copy(source)

    expect(snapshot).to eq("same" => { value: "second" })
    expect(snapshot).not_to be_compare_by_identity
    expect(snapshot.default).to be_nil
    expect(snapshot.keys.first).to be_frozen
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
  it "rejects custom numeric objects even when frozen or embedded in a Complex value" do
    numeric = Class.new(Numeric) do
      attr_reader :digits

      def initialize = @digits = []
    end.new
    values = [ numeric, Complex.rect(numeric, 0) ]
    values.each do |value|
      expect { CtxParser::Immutable.copy({ value: value }) }.to raise_error(ArgumentError, /plain data/)
    end
    numeric.freeze
    expect { CtxParser::Immutable.copy(numeric) }.to raise_error(ArgumentError, /plain data/)
    expect(numeric.digits).not_to be_frozen
  end
end
