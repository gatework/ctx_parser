# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_parser/values"

RSpec.describe CtxParser::Values do
  it "rejects ambiguous IPv4 leading zeros in both host and prefix conversions" do
    expect(described_class.ip_address?("192.168.001.1")).to be(false)
    expect { described_class.ipv4_prefix("192.168.001.1/24") }.to raise_error(ArgumentError)
  end

  it "returns false for address text with incompatible or invalid encodings" do
    [ "UTF-16LE", "UTF-16BE", "UTF-32LE", "UTF-32BE" ].each do |encoding|
      expect(described_class.ip_address?("192.0.2.1".encode(encoding))).to be(false)
    end
    expect(described_class.ip_address?("192.0.2.\xFF")).to be(false)
  end

  it "rejects nontext address identities and nonboolean host-bit policies at the boundary" do
    [ 12, false, [], {} ].each do |value|
      expect(described_class.ip_address?(value)).to be(false)
      expect { described_class.ip_address(value) }.to raise_error(ArgumentError)
      expect { described_class.mac_address(value) }.to raise_error(ArgumentError)
    end
    expect { described_class.ipv4_prefix("192.0.2.129/24", preserve_host_bits: "false") }.to raise_error(ArgumentError)
  end

  it "keeps absent values distinct from numeric zero" do
    expect(described_class.integer(nil)).to be_nil
    expect(described_class.integer("0")).to eq(0)
    expect(described_class.integer("007")).to eq(7)
    expect(described_class.integer(12)).to eq(12)
    expect(described_class.mac_address(nil)).to be_nil
    expect(described_class.ip_address(nil)).to be_nil
  end

  it "rejects partial and non-decimal numbers instead of coercing them" do
    [ "", "--", "N/A", "1.0", 1.0, "1e3", "0xff", "12junk", "-1", "+1", " 1", "1\n" ].each do |value|
      expect { described_class.integer(value) }.to raise_error(ArgumentError)
    end
  end

  it "honors inclusive caller-defined integer limits" do
    expect(described_class.integer("1", min: 1, max: 4094)).to eq(1)
    expect(described_class.integer("4094", min: 1, max: 4094)).to eq(4094)
    expect { described_class.integer("0", min: 1, max: 4094) }.to raise_error(described_class::OutOfRange)
    expect { described_class.integer("4095", min: 1, max: 4094) }.to raise_error(described_class::OutOfRange)
    expect(described_class.integer("4294967295", max: 4_294_967_295)).to eq(4_294_967_295)
    expect { described_class.integer("4294967296", max: 4_294_967_295) }.to raise_error(described_class::OutOfRange)
  end

  it "canonicalizes complete MAC addresses without loosening command grammars" do
    [ "AABBCCDDEEFF", "aabb.ccdd.eeff", "aabb-ccdd-eeff", "AA:BB:CC:DD:EE:FF" ].each do |value|
      expect(described_class.mac_address(value)).to eq("aa:bb:cc:dd:ee:ff")
    end
  end

  it "rejects malformed MAC addresses without stripping arbitrary characters" do
    [ "", "aa-bb-cc-dd-ee-ff", "aabbccddeef", "aabbccddeeff00", "aabb.ccdd.eefg", " aabb.ccdd.eeff", "aabb.ccdd.eeff\n" ].each do |value|
      expect { described_class.mac_address(value) }.to raise_error(ArgumentError)
    end
  end

  it "validates and canonicalizes IPv4 and IPv6 host addresses" do
    expect(described_class.ip_address("192.0.2.1")).to eq("192.0.2.1")
    expect(described_class.ip_address("2001:0db8:0:0::1")).to eq("2001:db8::1")
    expect(described_class.ip_address?("2001:db8::1")).to be(true)
    expect(described_class.ip_address?(nil)).to be(false)
    [ "", "--", "leaf.example.test", "192.0.2.999", "192.0.2.1/32", "2001:db8::1/128" ].each do |value|
      expect(described_class.ip_address?(value)).to be(false)
      expect { described_class.ip_address(value) }.to raise_error(ArgumentError)
    end
  end

  it "requires explicit permission for scoped IPv6 addresses" do
    expect(described_class.ip_address?("fe80::1%eth0")).to be(false)
    expect { described_class.ip_address("fe80::1%eth0") }.to raise_error(ArgumentError)
    expect(described_class.ip_address("fe80::1%eth0", allow_zone: true)).to eq("fe80::1%eth0")
    expect(described_class.ip_address?("fe80::1%eth0", allow_zone: true)).to be(true)
  end

  it "rejects nonboolean scope permissions instead of treating configuration text as approval" do
    [ "false", 0, :false, nil ].each do |permission|
      expect { described_class.ip_address("fe80::1%eth0", allow_zone: permission) }.to raise_error(ArgumentError)
      expect { described_class.ip_address("192.0.2.1", allow_zone: permission) }.to raise_error(ArgumentError)
      expect(described_class.ip_address?("fe80::1%eth0", allow_zone: permission)).to be(false)
    end
  end

  it "distinguishes an IPv4 interface address from its normalized network prefix" do
    expect(described_class.ipv4_prefix("192.0.2.129/24")).to eq("192.0.2.0/24")
    expect(described_class.ipv4_prefix("192.0.2.129/24", preserve_host_bits: true)).to eq("192.0.2.129/24")
    expect(described_class.ipv4_prefix("192.0.2.1/31")).to eq("192.0.2.0/31")
    expect(described_class.ipv4_prefix("192.0.2.1/32")).to eq("192.0.2.1/32")
    expect(described_class.ipv4_prefix("192.0.2.1/0")).to eq("0.0.0.0/0")
  end

  it "rejects missing, malformed and IPv6 prefixes rather than inferring an IPv4 network" do
    [ nil, "", "192.0.2.1", "192.0.2.1/33", "999.0.0.1/24", "192.0.2.1/255.255.255.0", "192.0.2.1/24\n", "2001:db8::1/64" ].each do |value|
      expect { described_class.ipv4_prefix(value) }.to raise_error(ArgumentError)
    end
  end

  it "requires integer or decimal text inputs without implicit object coercion" do
    object = Object.new
    def object.to_s = "123"
    [ :"123", object, true, false, -1 ].each do |raw|
      expect { described_class.integer(raw) }.to raise_error(ArgumentError, "Invalid decimal integer")
    end
  end

  it "validates integer limits even when the field is absent" do
    [ { min: false }, { max: false }, { min: "0" }, { max: 1.5 }, { min: 2, max: 1 } ].each do |limits|
      [ nil, "1", 1 ].each do |raw|
        expect { described_class.integer(raw, **limits) }.to raise_error(ArgumentError, "Invalid integer limits")
      end
    end
    expect(described_class.integer("0", min: nil, max: nil)).to eq(0)
    expect(described_class.integer("12", min: 12, max: 12)).to eq(12)
  end

  it "rejects mixed MAC separators rather than repairing an invalid identity" do
    [ "aabb.ccdd-eeff", "aabb-ccdd.eeff" ].each do |raw|
      expect { described_class.mac_address(raw) }.to raise_error(ArgumentError, "Invalid MAC address")
    end
  end
end
