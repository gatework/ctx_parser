# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/document"

RSpec.describe CtxParser::Document do
  it "shares the cursor and builds immutable source blocks through the common indentation reader" do
    text = "! generated\r\ninterface edge\r\n description uplink\n unknown command\r\nend\r\nhostname leaf"
    cursor = CtxParser::Cursor.new(text)
    document = described_class.new(cursor, comments: /\A!/, boundaries: /\Aend\z/)

    expect(document.cursor).to equal(cursor)
    expect(document.roots.map(&:text)).to eq([ "interface edge", "hostname leaf" ])
    expect(document.sections(/\Ainterface /)).to eq([ document.roots.first ])
    expect(document.roots.first).to be_a(CtxParser::Block)
    expect(document.roots.first.content).to eq("interface edge\r\n description uplink\n unknown command\r\n")
    expect(document.roots.first.line_range).to eq(2..4)
    expect(document.roots.first.children.map(&:text)).to eq([ "description uplink", "unknown command" ])
    expect(cursor.states).to eq(%i[ignored pending pending pending ignored pending])
    expect(document.issues).to eq([])
    expect(document.roots).to be_frozen
    expect(document.issues).to be_frozen
  end

  it "allows a stateful lexical policy without introducing a second tree builder" do
    policy = Class.new(described_class) do
      protected

      def classify(line)
        if line.text == "begin text"
          @opaque = true
          :ignored
        elsif line.text == "end text"
          @opaque = false
          :ignored
        elsif @opaque
          :ignored
        else
          super
        end
      end

      def finish
        issues << { code: :unclosed_text } if @opaque
      end
    end
    document = policy.new("begin text\nhostname forged\nend text\nhostname actual\nbegin text\nprivate-body\n")

    expect(document.roots.map(&:text)).to eq([ "hostname actual" ])
    expect(document.issues).to eq([ { code: :unclosed_text } ])
    expect(document.cursor.states).to eq(%i[ignored ignored ignored pending ignored ignored])
    expect(document.inspect).not_to include("private-body")
    expect(document.as_json.to_s).not_to include("private-body", "forged", "actual")
  end

  it "rejects an invalid policy response instead of silently dropping source lines" do
    policy = Class.new(described_class) do
      protected

      def classify(_line) = :skip_typo
    end

    expect { policy.new("hostname leaf\n") }.to raise_error(ArgumentError, "Invalid source line disposition")
  end
  it "owns immutable diagnostics after the lexical policy finishes" do
    diagnostic = { code: :unclosed_text, context: [ +"header" ] }
    policy = Class.new(described_class) do
      define_method(:finish) { issues << diagnostic }
    end
    document = policy.new("hostname leaf\n")
    diagnostic[:context].first.replace("changed")

    expect(document.issues).to eq([ { code: :unclosed_text, context: [ "header" ] } ])
    expect { document.issues.first[:context].clear }.to raise_error(FrozenError)
    expect(diagnostic).not_to be_frozen
  end
end
