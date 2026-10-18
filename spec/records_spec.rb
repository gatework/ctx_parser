# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/records"

RSpec.describe CtxParser::Records do
  it "keeps stable selections and distinguishes duplicate identities from extra rows" do
    rows = [
      { id: :a, value: 1 }, { id: :b, value: 2 }, { id: :c, value: 3 },
      { id: :a, value: 4 }, { id: :b, value: 5 }, { id: :a, value: 6 }, { id: :d, value: 7 }
    ]
    records = described_class.new(rows, identity: [ :id ])

    expect(records.first_occurrences).to eq(rows.values_at(0, 1, 2, 6))
    expect(records.unambiguous).to eq(rows.values_at(2, 6))
    expect(records.duplicate_identity_count).to eq(2)
    expect(records.duplicate_row_count).to eq(3)
    expect(records).to be_duplicates
    expect(records.rows).to eq(rows)
  end

  it "supports empty and conflict-free collections" do
    [ [], [ { id: 1 }, { id: 2 } ] ].each do |rows|
      records = described_class.new(rows, identity: [ :id ])

      expect(records.first_occurrences).to eq(rows)
      expect(records.unambiguous).to eq(rows)
      expect(records.duplicate_identity_count).to eq(0)
      expect(records.duplicate_row_count).to eq(0)
      expect(records).not_to be_duplicates
    end
  end

  it "compares composite identities and treats missing components consistently" do
    rows = [
      { "name" => "AP-1", "radio" => 1 }, { "name" => "AP-1", "radio" => 2 },
      { "name" => "AP-1", "radio" => 1 }, { "name" => "AP-2" }, { "name" => "AP-2", "radio" => nil }
    ]
    records = described_class.new(rows, identity: %w[name radio])

    expect(records.first_occurrences).to eq(rows.values_at(0, 1, 3))
    expect(records.unambiguous).to eq([ rows[1] ])
    expect(records.duplicate_identity_count).to eq(2)
    expect(records.duplicate_row_count).to eq(2)
  end

  it "evaluates a custom identity once per row and supports domain-specific exceptions" do
    rows = [
      { mac: "00:11:22:33:44:55", gateway: true, destination: "Lo0" },
      { mac: "00:11:22:33:44:55", destination: "Eth1/1" },
      { mac: "00:11:22:33:44:55", gateway: true, destination: "Lo1" },
      { mac: "00:11:22:33:44:55", destination: "Eth1/2" }
    ]
    visited = []
    records = described_class.new(rows, identity: [ :mac ]) do |row|
      visited << row
      row[:gateway] ? row.values_at(:mac, :gateway, :destination) : [ row[:mac] ]
    end

    expect(visited).to eq(rows)
    expect(records.first_occurrences).to eq(rows.values_at(0, 1, 2))
    expect(records.unambiguous).to eq(rows.values_at(0, 2))
    expect(records.duplicate_identity_count).to eq(1)
    expect(records.duplicate_row_count).to eq(1)
  end

  it "accepts a callable identity without field names" do
    identity = Class.new do
      def call(row) = row.fetch(:id).downcase
    end.new
    records = described_class.new([ { id: "AP-1" }, { id: "ap-1" } ], identity: identity)

    expect(records.first_occurrences).to eq([ { id: "AP-1" } ])
    expect(records.unambiguous).to be_empty
    expect(records).to be_duplicates
  end

  it "groups nil, false and custom equal keys while keeping numeric identities distinct" do
    key_type = Struct.new(:name) do
      def hash = name.downcase.hash
      def eql?(other) = other.instance_of?(self.class) && name.casecmp?(other.name)
    end
    keys = [ false, nil, key_type.new("AP"), 1, 1.0, false, nil, key_type.new("ap"), :unique ]
    rows = keys.map { |key| { id: key } }
    records = described_class.new(rows) { |row| row.fetch(:id) }

    expect(records.first_occurrences).to eq(rows.values_at(0, 1, 2, 3, 4, 8))
    expect(records.unambiguous).to eq(rows.values_at(3, 4, 8))
    expect(records.duplicate_identity_count).to eq(3)
    expect(records.duplicate_row_count).to eq(3)
  end

  it "evaluates every occurrence of a shared row reference and retains the first reference" do
    row = { id: :shared }
    calls = 0
    records = described_class.new([ row, row, row ]) do |entry|
      calls += 1
      entry.fetch(:id)
    end

    expect(calls).to eq(3)
    expect(records.rows.map(&:object_id)).to eq([ row.object_id ] * 3)
    expect(records.first_occurrences.first).to equal(row)
    expect(records.unambiguous).to be_empty
    expect(records.duplicate_identity_count).to eq(1)
    expect(records.duplicate_row_count).to eq(2)
  end

  it "keeps the original input order when an identity callback changes the caller array" do
    first, second, third = { id: :a }, { id: :b }, { id: :a }
    rows = [ first, second, third ]
    visited = []
    records = described_class.new(rows) do |row|
      visited << row.object_id
      rows.replace([ { id: :replacement } ])
      row.fetch(:id)
    end

    expect(visited).to eq([ first, second, third ].map(&:object_id))
    expect(records.first_occurrences.map(&:object_id)).to eq([ first, second ].map(&:object_id))
    expect(records.unambiguous.first).to equal(second)
    expect(records.duplicate_identity_count).to eq(1)
    expect(records.duplicate_row_count).to eq(1)
  end

  it "propagates an identity callback failure without visiting later rows" do
    rows = [ { id: :a }, { id: :b }, { id: :c } ]
    visited = []
    error = Class.new(StandardError).new

    expect do
      described_class.new(rows) do |row|
        visited << row.fetch(:id)
        raise error if row.fetch(:id) == :b

        row.fetch(:id)
      end
    end.to raise_error { |raised| expect(raised).to equal(error) }
    expect(visited).to eq([ :a, :b ])
    expect(rows).not_to be_frozen
  end

  it "protects its selections without freezing or modifying caller-owned records" do
    row = { id: 1 }
    rows = [ row ]
    records = described_class.new(rows, identity: [ :id ])
    rows << { id: 2 }

    expect(records.rows).to eq([ row ])
    expect(records.first_occurrences.first).to equal(row)
    expect(row).not_to be_frozen
    expect(records).to be_frozen
    [ records.rows, records.first_occurrences, records.unambiguous ].each do |selection|
      expect(selection).to be_frozen
    end
  end

  it "does not include raw record contents in diagnostics" do
    records = described_class.new([ { id: "secret-password" } ], identity: [ :id ])

    expect(records.inspect).to eq("#<CtxParser::Records size=1 duplicate_identities=0>")
    expect(records.inspect).not_to include("secret-password")
  end

  it "rejects invalid collections and missing identities" do
    [ nil, {}, [ "row" ] ].each do |rows|
      expect { described_class.new(rows, identity: [ :id ]) }.to raise_error(ArgumentError, "Records must be hashes")
    end
    [ nil, [], :id, "id" ].each do |identity|
      expect { described_class.new([], identity: identity) }
        .to raise_error(ArgumentError, "Identity must be a nonempty array or callable")
    end
  end
end
