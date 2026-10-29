# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe CtxParser::Result do
  it "includes covered scopes in every Ruby value operation" do
    scopes = [ { vrf: +"blue", process_id: +"1" } ]
    result = described_class.new(status: :complete, covered_scopes: scopes)
    other = result.with(covered_scopes: [ { vrf: "red", process_id: "1" } ])
    scopes.first[:vrf].replace("changed")
    expect(result.covered_scopes).to eq([ { vrf: "blue", process_id: "1" } ])
    expect(result.with(status: :partial).covered_scopes).to eq(result.covered_scopes)
    expect(result.to_h).to eq(result.deconstruct_keys(nil))
    expect(result.deconstruct.last).to eq(result.covered_scopes)
    expect(result).not_to eq(other)
    expect({ result => true }).not_to have_key(other)
    expect(scopes).not_to be_frozen
    expect { result.covered_scopes.first[:vrf].replace("bad") }.to raise_error(FrozenError)
  end

  it "does not attach coverage claims to unavailable results" do
    %i[failed unsupported].each do |status|
      expect { described_class.new(status: status, covered_scopes: [ { vrf: "blue" } ]) }.to raise_error(ArgumentError)
    end
  end

  it "rejects facts on unavailable results and keeps partial facts available" do
    %i[failed unsupported].each do |status|
      expect { described_class.new(status: status, records: [ { name: "eth0" } ]) }.to raise_error(ArgumentError)
      expect(described_class.new(status: status)).not_to be_available
    end
    partial = described_class.new(status: :partial, records: [ { name: "eth0" } ])
    expect(partial).to be_partial
    expect(partial).to be_available
    expect(described_class.new(status: :complete)).to be_available
  end

  it "rejects malformed diagnostics before they reach result aggregation or consumers" do
    [ nil, false, "invalid", {}, [ nil ], [ :invalid ], [ "invalid" ] ].each do |issues|
      expect { described_class.new(status: :partial, issues: issues) }.to raise_error(ArgumentError)
    end
    result = described_class.new(status: :partial, issues: [ { code: :incomplete_output } ])
    expect { result.with(issues: nil) }.to raise_error(ArgumentError)
    expect(CtxParser::Results.new(by_dimension: { interfaces: result }).issues).to eq([ { code: :incomplete_output } ])
  end

  it "omits facts and diagnostics from string interpolation as well as inspection" do
    result = described_class.new(status: :partial,
      records: [ { credential: "PRIVATE_FACT" } ], issues: [ { code: :invalid, detail: "PRIVATE_DIAGNOSTIC" } ])
    results = CtxParser::Results.new(by_dimension: { configuration: result })

    [ result, results ].each do |object|
      expect(object.to_s).to eq(object.inspect)
      expect("#{object}").not_to include("PRIVATE_FACT", "PRIVATE_DIAGNOSTIC")
    end
    expect(result.records.first[:credential]).to eq("PRIVATE_FACT")
    expect(result.issues.first[:detail]).to eq("PRIVATE_DIAGNOSTIC")
  end
end
