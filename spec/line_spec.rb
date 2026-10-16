# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/line"

RSpec.describe CtxParser::Line do
  it "retains the Data members and detaches source text from the caller" do
    raw = +" \tdescription edge\r\n"
    line = described_class.new(index: 2, raw: raw)
    raw.replace("changed")

    expect(line.members).to eq(%i[index raw])
    expect(line.to_h).to eq(index: 2, raw: " \tdescription edge\r\n")
    expect(line.text).to eq("description edge")
    expect(line.indent).to eq(2)
    expect(line.number).to eq(3)
    expect(raw).not_to be_frozen
  end

  it "protects the normalized text from mutation independently of the raw source" do
    line = described_class.new(index: 0, raw: " hostname LAB\n")

    expect { line.text.replace("hostname FORGED") }.to raise_error(FrozenError)
    expect(line.text).to eq("hostname LAB")
    expect(line.raw).to eq(" hostname LAB\n")
    expect(line.inspect).not_to include("LAB")
    expect(line.as_json).to eq(number: 1)
  end

  it "preserves empty lines, mixed indentation and missing final newlines" do
    [ [ "\r\n", "", 0 ], [ " \t \r", "", 3 ], [ "  end", "end", 2 ] ].each do |raw, text, indent|
      line = described_class.new(index: 0, raw: raw)
      expect(line.text).to eq(text)
      expect(line.indent).to eq(indent)
      expect(line.raw).to eq(raw)
    end
  end
end
