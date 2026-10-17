# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/input"

RSpec.describe CtxParser::Input do
  it "preserves raw line endings and detaches the text from its caller" do
    source = +"hostname leaf\r\nfeature bgp\rinterface nve1\n"
    original = source.dup
    parsed = described_class.text(source)
    source.clear

    expect(parsed).to eq(original)
    expect(parsed).not_to be_frozen
  end

  it "interprets binary input as UTF-8 while validating its bytes" do
    expect(described_class.text("description 无线".b).encoding).to eq(Encoding::UTF_8)
    expect { described_class.text("invalid\xFF".b) }.to raise_error(EncodingError)
    expect { described_class.text("invalid\xFF".dup.force_encoding(Encoding::UTF_8)) }.to raise_error(EncodingError)
  end

  it "keeps the declared encoding unless a caller asks to transcode" do
    latin = "description café".encode(Encoding::ISO_8859_1)

    expect(described_class.text(latin).encoding).to eq(Encoding::ISO_8859_1)
    expect(described_class.text(latin, encoding: :transcode)).to eq("description café")
    expect { described_class.text(latin, encoding: :utf8) }.to raise_error(EncodingError)
    expect(latin.encoding).to eq(Encoding::ISO_8859_1)
  end

  it "transcodes UTF-16 before checking logical NUL characters" do
    expect(described_class.text("description 无线".encode(Encoding::UTF_16LE), encoding: :transcode)).to eq("description 无线")
    expect { described_class.text("a\0b".encode(Encoding::UTF_16LE), encoding: :transcode) }.to raise_error(ArgumentError, /NUL/)
  end

  it "preserves valid non-ASCII-compatible encodings while checking logical NUL characters" do
    %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE UTF-16 UTF-32].each do |encoding|
      source = "description 无线".encode(encoding)
      value = described_class.text(source)

      expect(value.encoding).to eq(source.encoding)
      expect(value.bytes).to eq(source.bytes)
      expect(value).not_to equal(source)
      expect { described_class.text("a\0b".encode(encoding)) }.to raise_error(ArgumentError, /NUL/)
      expect(described_class.text("a\0b".encode(encoding), allow_nul: true).bytes).to eq("a\0b".encode(encoding).bytes)
    end
  end

  it "normalizes logical line endings without changing the declared encoding" do
    %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE UTF-16 UTF-32].each do |encoding|
      source = "first\r\n无线\rthird\n".encode(encoding)
      normalized = described_class.text(source, newlines: :lf)
      deleted = described_class.text(source, newlines: :delete_cr)

      expect(normalized.encoding).to eq(source.encoding)
      expect(normalized.encode(Encoding::UTF_8)).to eq("first\n无线\nthird\n")
      expect(deleted.encoding).to eq(source.encoding)
      expect(deleted.encode(Encoding::UTF_8)).to eq("first\n无线third\n")
    end
  end

  it "can reinterpret mislabeled UTF-8 bytes when that is the platform policy" do
    source = "description 无线".dup.force_encoding(Encoding::ISO_8859_1)

    expect(described_class.text(source, encoding: :utf8)).to eq("description 无线")
    expect(source.encoding).to eq(Encoding::ISO_8859_1)
  end

  it "distinguishes line-ending conversion from deleting carriage returns" do
    source = "first\r\nsecond\rthird\n"

    expect(described_class.text(source, newlines: :lf)).to eq("first\nsecond\nthird\n")
    expect(described_class.text(source, newlines: :delete_cr)).to eq("first\nsecondthird\n")
  end

  it "makes the NUL policy explicit without silently dropping bytes" do
    expect { described_class.text("first\0second") }.to raise_error(ArgumentError, /NUL/)
    expect(described_class.text("first\0second", allow_nul: true)).to eq("first\0second")
  end

  it "enforces byte limits before copying or transcoding the source" do
    expect(described_class.text("无线", max_bytes: 6)).to eq("无线")
    expect { described_class.text("无线", max_bytes: 5) }.to raise_error(ArgumentError, /byte limit/)
    expect(described_class.text("", max_bytes: 0)).to eq("")
    latin = "é".encode(Encoding::ISO_8859_1)
    expect(described_class.text(latin, encoding: :transcode, max_bytes: 1)).to eq("é")
  end

  it "rejects unsupported policies and non-text input" do
    [ nil, [], {} ].each { |value| expect { described_class.text(value) }.to raise_error(ArgumentError) }
    [ { encoding: :guess }, { newlines: :strip }, { allow_nul: nil }, { max_bytes: -1 }, { max_bytes: 1.5 } ].each do |options|
      expect { described_class.text("text", **options) }.to raise_error(ArgumentError)
    end
  end
end
