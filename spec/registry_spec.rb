# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe CtxParser::Registry do
  let(:profile) { Class.new(CtxParser::Profile) }

  it "rejects non-mapping declarations with a stable argument error" do
    [ nil, [], "platform" ].each do |invalid|
      expect { described_class.new(profiles: invalid) }.to raise_error(ArgumentError, "Registry declarations must be hashes")
      expect { described_class.new(profiles: { platform: profile }, aliases: invalid) }
        .to raise_error(ArgumentError, "Registry declarations must be hashes")
    end
  end

  it "normalizes platform names and aliases without retaining caller mappings" do
    name = +" PLATFORM "
    profiles, aliases = { name => profile }, { " Device " => :platform }
    registry = described_class.new(profiles: profiles, aliases: aliases)
    name.replace("changed")
    profiles.clear
    aliases.clear

    expect(registry.canonical(" DEVICE ")).to eq(:platform)
    expect(registry.fetch(" DEVICE ", model: " MODEL ")).to be_a(profile)
    expect(registry.fetch(:platform, model: " MODEL ").model).to eq("model")
    expect { registry.fetch(:missing) }.to raise_error(ArgumentError, "Unsupported parser platform")
  end

  it "rejects normalization collisions, alias chains and non-profile implementations" do
    [ { platform: profile, " PLATFORM " => profile }, { platform: Object } ].each do |profiles|
      expect { described_class.new(profiles: profiles) }.to raise_error(ArgumentError, "Invalid parser registry")
    end
    [ { platform: :platform }, { device: :absent }, { device: :alias, alias: :platform },
      { device: :platform, " DEVICE " => :platform } ].each do |aliases|
      expect { described_class.new(profiles: { platform: profile }, aliases: aliases) }.to raise_error(ArgumentError, "Invalid parser registry")
    end
  end
end
