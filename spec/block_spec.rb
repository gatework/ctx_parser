# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "rbconfig"
require "ctx_parser/parser"
require "ctx_parser/configuration_parser"

RSpec.describe CtxParser::Block do
  it "retains complete indentation blocks including unknown commands, comments, and blank lines" do
    text = "! generated\r\ninterface Ethernet1/1\r\n  description edge\n\n  unknown-setting enabled\r!\rinterface Ethernet1/2\n  shutdown"
    cursor = CtxParser::Cursor.new(text)
    blocks = described_class.read(cursor, comments: /\A!/)

    expect(blocks.map(&:text)).to eq([ "interface Ethernet1/1", "interface Ethernet1/2" ])
    expect(blocks.first.line_range).to eq(2..6)
    expect(blocks.first.content).to eq("interface Ethernet1/1\r\n  description edge\n\n  unknown-setting enabled\r!\r")
    expect(blocks.first.children.map(&:text)).to eq([ "description edge", "unknown-setting enabled" ])
    expect(blocks.last.line_range).to eq(7..8)
    expect(blocks.last.content).to eq("interface Ethernet1/2\n  shutdown")
    expect(blocks).to be_frozen
    expect(blocks.first).to be_frozen
    expect(blocks.first.children).to be_frozen
    expect(cursor.states).to eq(%i[ignored pending pending ignored pending ignored pending pending])
  end

  it "closes nested scopes at explicit boundaries without consuming the next block" do
    cursor = CtxParser::Cursor.new("wlan ap-group OFFICE\n ap-model WA\n  radio 1\n   service-template STAFF\n#\nwlan service-template STAFF\n ssid staff\nreturn\n")
    group, template = described_class.read(cursor, boundaries: /\A(?:#|return)\z/)

    expect(group.line_range).to eq(1..4)
    expect(group.children.first.line_range).to eq(2..4)
    expect(group.children.first.children.first.line_range).to eq(3..4)
    expect(group.content).to end_with("   service-template STAFF\n")
    expect(template.line_range).to eq(6..7)
    expect(template.content).to eq("wlan service-template STAFF\n ssid staff\n")
    expect(cursor.state(4)).to eq(:ignored)
    expect(cursor.state(7)).to eq(:ignored)
    expect(cursor).to be_eof
  end

  it "builds deeply nested source blocks without exhausting the Ruby call stack" do
    depth = 4_000
    text = (0...depth).map { |index| "#{' ' * index}setting #{index}\n" }.join
    cursor = CtxParser::Cursor.new(text)
    block = described_class.read(cursor).first

    expect(block.content).to eq(text)
    depth.times do |index|
      expect(block.line_range).to eq((index + 1)..depth)
      expect(block.text).to eq("setting #{index}")
      block = block.children.first
    end
    expect(block).to be_nil
    expect(cursor.states).to all(eq(:pending))
  end

  it "ignores a deep domain-external subtree without claiming its lines were parsed" do
    parser = Class.new(CtxParser::ConfigurationParser) do
      private

      def parse_output(text, complete:)
        read_configuration(text).each { |block| ignore(block) }
        CtxParser::Result.new(status: complete ? :complete : :partial)
      end
    end.new
    text = (0...4_000).map { |index| "#{' ' * index}unrelated\n" }.join

    expect(parser.parse(text, complete: true)).to be_complete
    expect(parser.cursor.states).to all(eq(:ignored))
    expect(parser.cursor.parsed_flags).to all(be(false))
    expect(parser.blocks.first).to be_complete
  end

  it "reports semantic completeness separately from tree construction and data capture" do
    cursor = CtxParser::Cursor.new("interface Ethernet1/1\n description edge\n unsupported-setting\n")
    block = described_class.read(cursor).first
    capture = cursor.capture(block, data: { description: "edge" }, path: [ :interfaces, "Ethernet1/1" ])

    expect(cursor.states).to eq(%i[pending pending pending])
    expect(capture).not_to be_complete
    cursor.mark(0)
    cursor.mark(1)
    cursor.mark(2, state: :unsupported)
    expect(block).not_to be_complete
    expect(cursor.unparsed_content).to eq(" unsupported-setting\n")
    cursor.mark(2, state: :ignored)
    expect(block).to be_complete
    expect(capture).to be_complete
    expect(capture.content).to eq(cursor.content)
  end

  it "keeps a deep immutable data snapshot and an independently copied record path" do
    cursor = CtxParser::Cursor.new("wlan service-template STAFF\n ssid staff\n")
    block = described_class.read(cursor).first
    name = +"STAFF"
    data = { name: name, configuration: { "rates" => [ +"6", 12, nil, true ] } }
    path = [ :service_templates, name ]
    capture = cursor.capture(block, data: data, path: path)
    name.replace("CHANGED")
    data[:configuration]["rates"].first.replace("54")
    path << :extra

    expect(capture.data).to eq(name: "STAFF", configuration: { "rates" => [ "6", 12, nil, true ] })
    expect(capture.path).to eq([ :service_templates, "STAFF" ])
    expect(capture).to be_frozen
    expect { capture.data[:configuration]["rates"] << 24 }.to raise_error(FrozenError)
    expect { capture.data[:name].replace("OTHER") }.to raise_error(FrozenError)
    expect { capture.path << :other }.to raise_error(FrozenError)
    expect(cursor.captures_for([ :service_templates, "STAFF" ])).to eq([ capture ])
  end

  it "retains every source of a repeated identity in document order" do
    cursor = CtxParser::Cursor.new("hostname FIRST\nhostname SECOND\n")
    blocks = described_class.read(cursor)
    captures = blocks.reverse.map { |block| cursor.capture(block, data: block.text.split.last, path: [ :hostname ]) }.reverse

    expect(cursor.captures_for([ :hostname ])).to eq(captures)
    expect(captures.map(&:content)).to eq([ "hostname FIRST\n", "hostname SECOND\n" ])
    expect(captures.map(&:line_range)).to eq([ 1..1, 2..2 ])
    expect(cursor.captures).to be_frozen
    expect(cursor.captures_for([ :hostname ])).to be_frozen
  end

  it "keeps direct Capture construction defensive even when caller containers are already frozen" do
    block = described_class.read(CtxParser::Cursor.new("hostname LEAF\n")).first
    name, key = +"LEAF", +"hostname"
    data, path = { name: name }.freeze, [ key ].freeze
    first = CtxParser::Capture.new(block: block, data: data, path: path)
    second = CtxParser::Capture.new(block: block, data: data, path: path)
    name.replace("CHANGED")
    key.replace("changed")

    expect(first.data).to eq(name: "LEAF")
    expect(first.path).to eq([ "hostname" ])
    expect(first.data).not_to equal(data)
    expect(first.data).not_to equal(second.data)
    expect(first.path).not_to equal(second.path)
    expect(name).not_to be_frozen
    expect(key).not_to be_frozen
  end

  it "rejects foreign blocks and invalid capture data without adding a capture" do
    cursor = CtxParser::Cursor.new("hostname LEAF\n")
    own_block = described_class.read(cursor).first
    foreign_block = described_class.read(CtxParser::Cursor.new("hostname SPINE\n")).first

    expect { cursor.capture(foreign_block, data: "SPINE", path: [ :hostname ]) }.to raise_error(ArgumentError)
    expect { cursor.capture(own_block, data: Object.new, path: [ :hostname ]) }.to raise_error(ArgumentError)
    expect { cursor.capture(own_block, data: "LEAF", path: [ Object.new ]) }.to raise_error(ArgumentError)
    expect(cursor.captures).to be_empty
  end

  it "keeps raw secrets available explicitly while omitting them from normal inspection" do
    cursor = CtxParser::Cursor.new("wlan service-template STAFF\n preshared-key simple SECRET_SENTINEL\n")
    block = described_class.read(cursor).first
    capture = cursor.capture(block, data: { has_preshared_key: true }, path: [ :service_templates, "STAFF" ])

    expect(capture.content).to include("SECRET_SENTINEL")
    [ cursor, block, block.children.last.header, capture ].each do |object|
      expect(object.inspect).not_to include("SECRET_SENTINEL")
      expect(object.to_s).not_to include("SECRET_SENTINEL")
    end
  end

  it "keeps each parse's sources independent and clears stale state before rejecting new input" do
    parser = Class.new(CtxParser::Parser) do
      private

      def parse_output(text, complete:)
        read_configuration(text)
        CtxParser::Result.new(status: complete ? :complete : :partial)
      end
    end.new

    result = parser.parse("hostname FIRST\n", complete: true)
    original_cursor, original_block = parser.cursor, parser.blocks.first
    parser.parse("hostname SECOND\n", complete: true)
    expect(parser.cursor).not_to equal(original_cursor)
    expect(original_block.content).to eq("hostname FIRST\n")
    expect(parser.blocks.first.content).to eq("hostname SECOND\n")
    expect(result.to_h.keys).to contain_exactly(:status, :records, :issues)
    expect { parser.parse(nil) }.to raise_error(ArgumentError)
    expect(parser.cursor).to be_nil
    expect(parser.blocks).to be_empty
  end
end
