# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Owned declaration and source containers" do
  def decorated(values)
    Class.new(Array).new(values).tap do |array|
      def array.dup = self
      def array.map = self
    end
  end

  it "owns declaration arrays without retaining their copy hooks" do
    parser = Class.new(CtxParser::Parser)
    dimensions = decorated([ :inventory ])
    entries = decorated([ { dimensions: dimensions, command: "show inventory", parser: parser } ])
    catalog = CtxParser::Commands.new(entries)
    expect(entries).not_to be_frozen
    expect(dimensions).not_to be_frozen
    entries.clear
    dimensions.clear
    expect(catalog.commands_for(:inventory)).to eq([ "show inventory" ])
    expect(catalog.entries).to be_instance_of(Array)
    expect(catalog.entries.first[:dimensions]).to be_instance_of(Array)
  end

  it "fixes the request before a parser callback mutates the caller selection" do
    dimensions = decorated(%i[inventory counters])
    parser = Class.new(CtxParser::Parser)
    parser.define_singleton_method(:parse) do |*, **|
      dimensions.clear
      CtxParser::Result.new(status: :complete)
    end
    catalog = CtxParser::Commands.new([ { dimensions: %i[inventory counters], command: "show inventory", parser: parser } ])
    result = CtxParser::Profile.new(declarations: catalog).parse_many(dimensions, "body")
    expect(result.keys).to eq(%i[inventory counters])
    expect(dimensions).to be_empty
  end

  it "borrows records while owning the caller list before identity callbacks" do
    row = { id: 1 }
    rows = decorated([ row, row ])
    records = CtxParser::Records.new(rows) { |entry| rows.clear; entry[:id] }
    expect(records.rows).to be_instance_of(Array)
    expect(records.rows).to eq([ row, row ])
    expect(records.first_occurrences.first).to equal(row)
    expect(row).not_to be_frozen
    expect(records.duplicate_row_count).to eq(1)
  end

  it "owns child membership without taking ownership of source blocks" do
    document = CtxParser::Document.new("parent\n child\n")
    parent = document.roots.first
    children = decorated(parent.children)
    copy = CtxParser::Block.new(cursor: document.cursor, header: parent.header, children: children, last_index: parent.last_index)
    expect(children).not_to be_frozen
    children.clear
    expect(copy.children).to eq(parent.children)
    expect(copy.children.first).to equal(parent.children.first)
  end

  it "fixes capture membership before copying facts invokes an input callback" do
    cursor = CtxParser::Cursor.new("first\nsecond\n")
    blocks = CtxParser::Block.read(cursor)
    [ false, true ].each do |through_cursor|
      sources = decorated(blocks)
      data = { name: "fact" }
      data.define_singleton_method(:each_pair) do |&block|
        sources.clear
        super(&block)
      end
      captures = if through_cursor
        cursor.capture_many(sources, data: data, path: [ :fact ])
      else
        CtxParser::Capture.for_blocks(sources, data: data, path: [ :fact ])
      end
      expect(captures.map(&:block)).to eq(blocks)
      expect(captures.first.data).to eq(name: "fact")
      expect(sources).to be_empty
    end
  end
end
