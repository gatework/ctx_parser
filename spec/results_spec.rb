# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe CtxParser::Results do
  let(:complete) { CtxParser::Result.new(status: :complete, records: [ { name: "port1" } ]) }

  it "requires named dimensions that can be selected by a command profile" do
    [ nil, "", "interfaces", :"", [], {} ].each do |name|
      expect { described_class.new(by_dimension: { name => complete }) }.to raise_error(ArgumentError)
    end
    expect { described_class.new(by_dimension: {}) }.to raise_error(ArgumentError)
    expect { described_class.new(by_dimension: { interfaces: {} }) }.to raise_error(ArgumentError)
  end

  it "detaches the result mapping without copying already immutable results" do
    source = { interfaces: complete }
    results = described_class.new(by_dimension: source)
    source.clear

    expect(results.fetch(:interfaces)).to equal(complete)
    expect { results.fetch(:missing) }.to raise_error(KeyError)
    expect { results.by_dimension.clear }.to raise_error(FrozenError)
    expect(results).to be_complete
  end

  it "preserves independent statuses and deduplicates shared diagnostics" do
    issue = { code: :incomplete_output }
    partial = CtxParser::Result.new(status: :partial, issues: [ issue ])
    failed = CtxParser::Result.new(status: :failed, issues: [ issue ])
    unsupported = CtxParser::Result.new(status: :unsupported)

    expect(described_class.new(by_dimension: { interfaces: complete, counters: failed }).status).to eq(:partial)
    expect(described_class.new(by_dimension: { interfaces: partial, counters: failed }).issues).to eq([ issue ])
    expect(described_class.new(by_dimension: { interfaces: failed, counters: unsupported }).status).to eq(:failed)
    expect(described_class.new(by_dimension: { interfaces: unsupported, counters: unsupported }).status).to eq(:unsupported)
  end

  it "drops hash defaults so an undeclared dimension cannot produce evidence or run caller code" do
    calls = []
    sources = [ Hash.new(complete), Hash.new { |_hash, name| calls << name; complete } ]
    sources.each do |source|
      source[:interfaces] = complete
      results = described_class.new(by_dimension: source)

      expect(results.by_dimension[:missing]).to be_nil
      expect(results).not_to be_key(:missing)
      expect { results.fetch(:missing) }.to raise_error(KeyError)
      expect(results.fetch(:interfaces)).to equal(complete)
      expect(results.by_dimension.default_proc).to be_nil
    end
    expect(calls).to be_empty
  end
end
