# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Native configuration sources" do
  it "builds an explicit hierarchy without requiring indentation and preserves closing lines" do
    native = Class.new(CtxParser::Document) do
      protected

      def build_blocks
        header = cursor.read
        child = CtxParser::Block.new(cursor: cursor, header: cursor.read, children: [], last_index: 2)
        [ CtxParser::Block.new(cursor: cursor, header: header, children: [ child ], last_index: 3) ]
      end
    end
    source = "config addresses\r\nedit host\r\nnext\r\nend\r\n"
    cursor = CtxParser::Cursor.new(source)
    cursor.read
    document = native.new(cursor)
    block = document.roots.fetch(0)

    expect(block.content).to eq(source)
    expect(block.children.first.content).to eq("edit host\r\nnext\r\n")
    expect(document.roots.size).to eq(1)
    expect(cursor.states).to eq([ :pending ] * 4)
    expect(document.roots).to be_frozen
  end

  it "snapshots native root arrays without inheriting their copy or traversal hooks" do
    native = Class.new(CtxParser::Document) do
      protected

      def build_blocks
        roots = [ cursor.block(0) ]
        roots.define_singleton_method(:dup) { [] }
        roots.define_singleton_method(:all?) { raise "caller traversal hook" }
        roots
      end
    end
    document = native.new("root\n")
    expect(document.roots).to be_instance_of(Array)
    expect(document.roots.map(&:text)).to eq([ "root" ])
    expect(document.roots).to be_frozen
  end

  it "rejects overlapping and foreign roots returned by a native builder" do
    foreign = CtxParser::Document.new("foreign\n").roots.first
    [ :overlapping, :reversed, :foreign ].each do |kind|
      native = Class.new(CtxParser::Document) do
        define_method(:build_blocks) do
          first = CtxParser::Block.new(cursor: cursor, header: cursor.lines[0], children: [], last_index: 1)
          second = cursor.block(1)
          { overlapping: [ first, second ], reversed: [ second, first ], foreign: [ foreign ] }.fetch(kind)
        end
      end
      expect { native.new("first\nsecond\n") }.to raise_error(ArgumentError)
    end
  end

  it "keeps flat command lines independent and captures their live state across rescans" do
    document = CtxParser::Document::Flat.new("set first\n  set second\r\n")
    cursor = document.cursor
    expect(document.roots.map(&:line_range)).to eq([ 1..1, 2..2 ])
    expect(document.roots.map(&:children)).to eq([ [], [] ])
    block = cursor.block(1)
    capture = cursor.capture(block, data: { name: "second" }, path: [ :objects, 1 ])
    cursor.mark(1)
    cursor.rewind
    expect(cursor.read_pending.number).to eq(1)
    expect(cursor.read_pending).to be_nil
    expect(capture).to be_complete
    cursor.reset!
    expect(cursor.block(1)).to equal(block)
    expect(capture).not_to be_complete
    expect(cursor.captures).to be_empty
    expect(block.content).to eq("  set second\r\n")
    expect { cursor.block(-1) }.to raise_error(IndexError)
  end
end
