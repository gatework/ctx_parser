# frozen_string_literal: true

module CtxParser
  # 复制并冻结普通数据，避免解析快照共享调用方可变状态。
  module Immutable
    # 深度复制并冻结普通数据，拒绝可执行或不支持的对象。
    def self.copy(value)
      # 容器已冻结也可能持有可变子对象，仍须递归复制；冻结字符串可直接复用。
      case value
      when Hash then value.to_h { |key, item| [ copy(key), copy(item) ] }.freeze
      when Array then value.map { |item| copy(item) }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      when Symbol, Numeric, NilClass, TrueClass, FalseClass then value
      else raise ArgumentError, "Values must contain plain data"
      end
    end
  end
end
