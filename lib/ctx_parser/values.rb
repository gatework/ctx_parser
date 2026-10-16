# frozen_string_literal: true

require "ipaddr"

module CtxParser
  # 严格转换标量；单位及可选字段语法仍由命令解析器负责。
  module Values
    class OutOfRange < ArgumentError; end

    module_function

    # 解析十进制整数，并校验声明的边界。
    def integer(raw, min: 0, max: nil)
      return if raw.nil?
      raise ArgumentError, "Invalid decimal integer" unless /\A\d+\z/.match?(raw.to_s)

      value = Integer(raw.to_s, 10)
      raise OutOfRange, "Integer out of range" if (min && value < min) || (max && value > max)

      value
    end

    # 归一化 MAC 地址，拒绝格式错误的输入。
    def mac(raw)
      return if raw.nil?
      unless /\A(?:[0-9a-f]{12}|(?:[0-9a-f]{4}[-.]){2}[0-9a-f]{4}|(?:[0-9a-f]{2}:){5}[0-9a-f]{2})\z/i.match?(raw)
        raise ArgumentError, "Invalid MAC address"
      end

      raw.delete("-.:").downcase.scan(/../).join(":")
    end

    # 归一化主机地址，保留 IPv4 与 IPv6 语义。
    def host(raw, allow_zone: false)
      return if raw.nil?
      raise ArgumentError, "Invalid host address" if raw.include?("/") || (!allow_zone && raw.include?("%"))

      IPAddr.new(raw).to_s
    end

    # 校验主机地址有效性，不让格式错误值继续传播。
    def valid_host?(raw, allow_zone: false)
      !host(raw, allow_zone: allow_zone).nil?
    rescue ArgumentError, IPAddr::Error
      false
    end

    # 统一校验网段与接口地址，仅接口投影保留主机位。
    def ipv4_prefix(raw, host: false)
      unless raw.is_a?(String) && raw.match?(%r{\A\d+(?:\.\d+){3}/\d+\z})
        raise ArgumentError, "IPv4 prefix required"
      end
      network = IPAddr.new(raw)
      raise ArgumentError, "IPv4 prefix required" unless network.ipv4?

      host ? raw : "#{network}/#{network.prefix}"
    end
  end
end
