# frozen_string_literal: true

require "ipaddr"

module CtxParser
  # 严格转换标量；单位及可选字段语法仍由命令解析器负责。
  module Values
    class OutOfRange < ArgumentError; end

    module_function

    # 解析十进制整数，并校验声明的边界。
    def integer(raw, min: 0, max: nil)
      unless (min.nil? || min.is_a?(Integer)) && (max.nil? || max.is_a?(Integer)) && (min.nil? || max.nil? || min <= max)
        raise ArgumentError, "Invalid integer limits"
      end
      return if raw.nil?
      pattern = min.nil? || min.negative? ? /\A-?\d+\z/ : /\A\d+\z/
      unless (raw.is_a?(String) || raw.is_a?(Integer)) && pattern.match?(raw.to_s)
        raise ArgumentError, "Invalid decimal integer"
      end

      value = raw.is_a?(Integer) ? raw : Integer(raw, 10)
      raise OutOfRange, "Integer out of range" if (min && value < min) || (max && value > max)

      value
    end

    # 归一化 MAC 地址，拒绝格式错误的输入。
    def mac_address(raw)
      return if raw.nil?
      unless raw.is_a?(String) && /\A(?:[0-9a-f]{12}|[0-9a-f]{4}([-.])[0-9a-f]{4}\1[0-9a-f]{4}|(?:[0-9a-f]{2}:){5}[0-9a-f]{2})\z/i.match?(raw)
        raise ArgumentError, "Invalid MAC address"
      end

      raw.delete("-.:").downcase.scan(/../).join(":")
    end

    # 归一化主机地址，保留 IPv4 与 IPv6 语义。
    def ip_address(raw, allow_zone: false)
      raise ArgumentError, "Zone permission must be boolean" unless [ true, false ].include?(allow_zone)
      return if raw.nil?
      raise ArgumentError, "Invalid IP address" unless raw.is_a?(String)
      raise ArgumentError, "Invalid IP address" if raw.include?("/") || (!allow_zone && raw.include?("%"))

      IPAddr.new(raw).to_s
    end

    # 校验主机地址有效性，不让格式错误值继续传播。
    def ip_address?(raw, allow_zone: false)
      !ip_address(raw, allow_zone: allow_zone).nil?
    rescue ArgumentError, IPAddr::Error, EncodingError
      false
    end

    # 统一校验网段与接口地址，仅接口投影保留主机位。
    def ipv4_prefix(raw, preserve_host_bits: false)
      raise ArgumentError, "Host-bit preservation must be boolean" unless [ true, false ].include?(preserve_host_bits)
      unless raw.is_a?(String) && raw.match?(%r{\A\d+(?:\.\d+){3}/\d+\z})
        raise ArgumentError, "IPv4 prefix required"
      end
      network = IPAddr.new(raw)
      raise ArgumentError, "IPv4 prefix required" unless network.ipv4?

      preserve_host_bits ? raw.dup : "#{network}/#{network.prefix}"
    end
  end
end
