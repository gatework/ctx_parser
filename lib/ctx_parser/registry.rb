# frozen_string_literal: true

require_relative "profile"

module CtxParser
  # 各领域独立持有注册表；不支持的平台直接拒绝，不猜测其他厂商语法。
  class Registry
    # 注册平台策略及其声明的别名。
    def initialize(profiles:, aliases: {})
      @profiles = profiles.transform_keys { |key| platform_key(key) }.freeze
      @aliases = aliases.transform_keys { |key| platform_key(key) }.transform_values { |key| platform_key(key) }.freeze
      unless @profiles.size == profiles.size && @aliases.size == aliases.size &&
          @profiles.values.all? { |profile| profile.is_a?(Class) && profile < Profile } &&
          @aliases.values.all? { |key| @profiles.key?(key) } && (@profiles.keys & @aliases.keys).empty?
        raise ArgumentError, "Invalid parser registry"
      end
    end

    # 解析请求的解析结果或平台策略，拒绝未知名称。
    def fetch(platform, model: nil)
      key = platform_key(platform)
      key = @aliases.fetch(key, key)
      profile = @profiles.fetch(key) { raise ArgumentError, "Unsupported parser platform" }
      profile.new(model: model)
    end

    private

    # 选择已注册平台策略前，先归一化平台别名。
    def platform_key(value)
      raise ArgumentError, "Parser platform must be a name" unless value.is_a?(String) || value.is_a?(Symbol)

      key = value.to_s.strip.downcase
      raise ArgumentError, "Parser platform must be a name" if key.empty?

      key.to_sym
    end
  end
end
