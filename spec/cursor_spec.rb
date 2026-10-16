# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/parser"

RSpec.describe CtxParser::Cursor do
  it "preserves mixed original line endings and detaches the source from its caller" do
    input = +"hostname LEAF\r\nfeature bgp\rinterface Ethernet1/1\n  description edge"
    original = input.dup
    cursor = described_class.new(input)
    input.replace("changed")

    expect(cursor.content).to eq(original)
    expect(cursor.lines.map(&:raw)).to eq([ "hostname LEAF\r\n", "feature bgp\r", "interface Ethernet1/1\n", "  description edge" ])
    expect(cursor.lines.map(&:number)).to eq([ 1, 2, 3, 4 ])
    expect(cursor.lines.last.text).to eq("description edge")
    expect(cursor.lines.last.indent).to eq(2)
    expect(cursor.checksum).to eq(Digest::SHA256.hexdigest(original))
    expect(cursor.content).to be_frozen
    expect(cursor.lines).to be_frozen
    expect(cursor.lines.map(&:raw)).to all(be_frozen)
  end

  it "reads and peeks without claiming that the visited lines were parsed" do
    cursor = described_class.new("hostname LEAF\nfeature bgp\n")

    expect(cursor.peek.number).to eq(1)
    expect(cursor.position).to eq(0)
    expect(cursor.visited?(0)).to be(false)
    expect(cursor.read).to equal(cursor.lines.first)
    expect(cursor.position).to eq(1)
    expect(cursor.visited?(0)).to be(true)
    expect(cursor.parsed?(0)).to be(false)
    expect(cursor.states).to eq(%i[pending pending])
  end

  it "keeps EOF and backward navigation within the source boundaries" do
    cursor = described_class.new("hostname LEAF")
    expect(cursor.step_back).to be(false)
    expect(cursor.unread).to be(false)
    expect(cursor.defer).to be(false)
    cursor.read
    expect(cursor).to be_eof
    2.times { expect(cursor.read).to be_nil }
    expect(cursor.peek).to be_nil
    expect(cursor.position).to eq(1)
    expect(cursor.step_back).to be(true)
    expect(cursor.read.text).to eq("hostname LEAF")

    empty = described_class.new("")
    expect(empty).to be_eof
    expect(empty.read).to be_nil
    expect(empty.position).to eq(0)
    expect(empty.lines).to be_empty
  end

  it "finds pending lines without changing their semantic state or dropping blank lines" do
    cursor = described_class.new("done\n\nunknown\nnext\n")
    cursor.mark(0)
    cursor.mark(2, state: :unsupported)

    expect(cursor.read_pending.number).to eq(2)
    expect(cursor.state(1)).to eq(:pending)
    expect(cursor.read_pending.number).to eq(4)
    expect(cursor.read_pending).to be_nil
    expect(cursor.states).to eq(%i[parsed pending unsupported pending])
    expect((0...cursor.size).map { |index| cursor.visited?(index) }).to all(be(true))
  end

  it "distinguishes moving backward, unreading, and deferring a line" do
    cursor = described_class.new("first\nsecond\n")
    cursor.read
    cursor.mark(0)
    cursor.read
    cursor.mark(1, state: :invalid)

    expect(cursor.step_back).to be(true)
    expect(cursor.state(1)).to eq(:invalid)
    cursor.read
    expect(cursor.defer).to be(true)
    expect(cursor.position).to eq(2)
    expect(cursor.state(1)).to eq(:pending)
    cursor.mark(1)
    expect(cursor.unread).to be(true)
    expect(cursor.position).to eq(1)
    expect(cursor.state(1)).to eq(:pending)
    expect(cursor.visited?(1)).to be(true)
    expect(cursor.state(0)).to eq(:parsed)
  end

  it "rewinds without losing state but resets a fresh analysis completely" do
    cursor = described_class.new("hostname LEAF\n")
    block = CtxParser::Block.read(cursor).first
    cursor.mark(0)
    capture = cursor.capture(block, data: "LEAF", path: [ :hostname ])
    states = cursor.states

    expect(cursor.rewind).to equal(cursor)
    expect(cursor.position).to eq(0)
    expect(cursor.visited?(0)).to be(true)
    expect(cursor.parsed_flags).to eq([ true ])
    expect(cursor.captures).to eq([ capture ])
    expect(cursor.reset!).to equal(cursor)
    expect(cursor.states).to eq([ :pending ])
    expect(cursor.visited?(0)).to be(false)
    expect(cursor.captures).to be_empty
    expect(cursor.content).to eq("hostname LEAF\n")
    expect(states).to eq([ :parsed ])
    expect(states).to be_frozen
  end

  it "returns unresolved raw text while excluding parsed and intentionally ignored lines" do
    cursor = described_class.new("parsed\r\n! comment\rpending\nunknown\ninvalid")
    cursor.mark(0)
    cursor.mark(1, state: :ignored)
    cursor.mark(3, state: :unsupported)
    cursor.mark(4, state: :invalid)

    expect(cursor.unparsed_lines.map(&:number)).to eq([ 3, 4, 5 ])
    expect(cursor.unparsed_content).to eq("pending\nunknown\ninvalid")
    expect(cursor.unparsed_lines).to be_frozen
    expect(cursor.unparsed_content).to be_frozen
    expect(cursor.parsed_flags).to eq([ true, false, false, false, false ])
  end

  it "rejects invalid state changes without modifying the analysis" do
    cursor = described_class.new("hostname LEAF\n")
    [ -1, 1, "0", nil ].each do |index|
      expect { cursor.mark(index) }.to raise_error(IndexError)
      expect { cursor.state(index) }.to raise_error(IndexError)
      expect(cursor.parsed?(index)).to be_nil
      expect(cursor.visited?(index)).to be_nil
    end
    expect { cursor.mark(0, state: true) }.to raise_error(ArgumentError)
    expect(cursor.states).to eq([ :pending ])
  end

  it "shares one defensive value snapshot across a batch without freezing caller data" do
    cursor = described_class.new("ntp server 192.0.2.1\nntp server 192.0.2.2\n")
    blocks = CtxParser::Block.read(cursor)
    servers = [ +"192.0.2.1", +"192.0.2.2" ]
    path = [ +"facts", +"ntp.servers" ]
    captured = cursor.capture_many(blocks, data: servers, path: path)
    servers.first.replace("192.0.2.3")
    path.last.replace("changed")

    expect(captured).to be_frozen
    expect(captured.map(&:data)).to eq([ [ "192.0.2.1", "192.0.2.2" ] ] * 2)
    expect(captured.last.data).to equal(captured.first.data)
    expect(captured.last.path).to equal(captured.first.path)
    expect(captured.map(&:line_range)).to eq([ 1..1, 2..2 ])
    expect(captured.first.path).to eq([ "facts", "ntp.servers" ])
    expect { captured.first.data.first.replace("changed") }.to raise_error(FrozenError)
    expect(cursor.states).to eq(%i[pending pending])
    later = cursor.capture_many(blocks, data: servers, path: [ "facts", "ntp.servers" ])
    expect(later.first.data).not_to equal(captured.first.data)
    expect(later.first.data).to eq([ "192.0.2.3", "192.0.2.2" ])
    expect(captured.first.data).to eq([ "192.0.2.1", "192.0.2.2" ])
  end

  it "validates an entire capture batch before adding or invalidating existing selections" do
    cursor = described_class.new("hostname LEAF\nfeature bgp\n")
    blocks = CtxParser::Block.read(cursor)
    foreign = CtxParser::Document.new("hostname OTHER\n").roots.first
    original = cursor.capture(blocks.first, data: "LEAF", path: [ :hostname ])
    all = cursor.captures
    selected = cursor.captures_for([ :hostname ])
    [ [ blocks.first, foreign ], [ blocks.first, nil ], nil ].each do |invalid|
      expect { cursor.capture_many(invalid, data: "value", path: [ :hostname ]) }.to raise_error(ArgumentError)
    end
    expect { cursor.capture_many(blocks, data: Object.new, path: [ :hostname ]) }.to raise_error(ArgumentError)
    expect { cursor.capture_many(blocks, data: "value", path: [ Object.new ]) }.to raise_error(ArgumentError)
    expect(cursor.captures).to eq([ original ])
    expect(cursor.captures_for([ :hostname ])).to eq([ original ])
    expect(all).to eq([ original ])
    expect(selected).to eq([ original ])
    expect(cursor.capture_many([], data: "value", path: [ :hostname ])).to eq([])
    expect(cursor.captures).to eq([ original ])
  end

  it "preserves document and same-line capture order when path selections are queried before more captures" do
    cursor = described_class.new("first\nsecond\nthird\n")
    blocks = CtxParser::Block.read(cursor)
    batch = cursor.capture_many([ blocks[1], blocks[0], blocks[0] ], data: "initial", path: [ :shared ])
    earlier = cursor.captures_for([ :shared ])
    expect(earlier).to eq([ batch[1], batch[2], batch[0] ])
    other = cursor.capture(blocks[2], data: "other", path: [ :other ])
    expect(cursor.captures_for([ :missing ])).to eq([])
    last = cursor.capture(blocks[0], data: "later", path: [ :shared ])

    expect(cursor.captures_for([ :shared ])).to eq([ batch[1], batch[2], last, batch[0] ])
    expect(cursor.captures_for([ :other ])).to eq([ other ])
    expect(cursor.captures).to eq([ batch[1], batch[2], last, batch[0], other ])
    expect(earlier).to eq([ batch[1], batch[2], batch[0] ])
    expect(earlier).to be_frozen
    query = [ :shared ]
    expect(cursor.captures_for(query).size).to eq(4)
    query << :mutated
    expect(cursor.captures_for([ :shared ]).size).to eq(4)
  end

  it "clears indexed captures on reset while keeping captured completeness tied to live line states" do
    cursor = described_class.new("first\nsecond\n")
    blocks = CtxParser::Block.read(cursor)
    captured = cursor.capture_many(blocks, data: "shared", path: [ :shared ])
    earlier = cursor.captures_for([ :shared ])
    expect(captured.first).not_to be_complete
    cursor.mark(0)
    expect(captured.first).to be_complete
    expect(captured.last).not_to be_complete
    cursor.reset!

    expect(captured.first).not_to be_complete
    expect(cursor.captures).to be_empty
    expect(cursor.captures_for([ :shared ])).to be_empty
    expect(earlier).to eq(captured)
    current = cursor.capture(blocks.last, data: "new", path: [ :shared ])
    expect(cursor.captures_for([ :shared ])).to eq([ current ])
    expect(earlier).to eq(captured)
  end

  it "accepts valid binary UTF-8 and rejects malformed or NUL-containing input" do
    expect(described_class.new("description 无线\n".b).content.encoding).to eq(Encoding::UTF_8)
    expect { described_class.new(nil) }.to raise_error(ArgumentError)
    expect { described_class.new("invalid\xFF".b) }.to raise_error(EncodingError)
    expect { described_class.new("hostname\0LEAF") }.to raise_error(ArgumentError)
  end
end
