# frozen_string_literal: true

module CtxParser
  # 复制并冻结普通数据，避免解析快照共享调用方可变状态。
  module Immutable
    COPYING = Object.new.freeze
    private_constant :COPYING

    # 同一容器只复制一次；循环数据不是普通值，须在越过快照边界前拒绝。
    def self.copy(value)
      copy_value(value, {}.compare_by_identity, 0)
    end

    # 普通常量浅树沿用 Ruby 的映射；递归深度有界，深链交给显式后序栈。
    def self.copy_value(value, copies, depth)
      case value
      when Hash, Array
        if (snapshot = copies[value])
          raise ArgumentError, "Values must not contain cyclic data" if snapshot.equal?(COPYING)

          return snapshot
        end
        return copy_deep(value, copies) if depth == 64

        copies[value] = COPYING
        if reusable?(value, copies, depth)
          copies[value] = value
          return value
        end
        copies[value] = if value.is_a?(Hash)
          result = {}
          value.each_pair { |key, item| result[copy_value(key, copies, depth + 1)] = copy_value(item, copies, depth + 1) }
          result.freeze
        else
          value.map { |item| copy_value(item, copies, depth + 1) }.freeze
        end
      when String then value.frozen? ? value : value.dup.freeze
      when Symbol, Integer, Float, Rational, NilClass, TrueClass, FalseClass then value
      when Complex
        # Complex 自身冻结，但可包含调用方定义的可变 Numeric 分量。
        copy_value(value.real, copies, depth + 1)
        copy_value(value.imaginary, copies, depth + 1)
        value
      else raise ArgumentError, "Values must contain plain data"
      end
    end
    private_class_method :copy_value

    # 仅复用无特殊 Hash 行为的深冻结普通容器；逐层验证，不信任外层 frozen?。
    def self.reusable?(value, copies, depth)
      return false unless value.frozen? && value.instance_variables.empty?
      if value.instance_of?(Array)
        value.all? { |item| copy_value(item, copies, depth + 1).equal?(item) }
      elsif value.instance_of?(Hash) && value.default.nil? && !value.default_proc && !value.compare_by_identity?
        value.each_pair do |key, item|
          return false unless copy_value(key, copies, depth + 1).equal?(key) && copy_value(item, copies, depth + 1).equal?(item)
        end
        true
      else
        false
      end
    end
    private_class_method :reusable?

    # 容器缓存按来源身份查找，普通 Hash 的键仍沿用值相等语义。
    def self.copy_deep(value, copies)
      pending = [ [ value, false ] ]
      until pending.empty?
        source, finishing = pending.pop
        if finishing
          copies[source] = if reusable?(source, copies, 0)
            source
          elsif source.is_a?(Hash)
            result = {}
            source.each_pair { |key, item| result[snapshot(key, copies)] = snapshot(item, copies) }
            result.freeze
          else
            source.map { |item| snapshot(item, copies) }.freeze
          end
          next
        end
        if (existing = copies[source])
          raise ArgumentError, "Values must not contain cyclic data" if existing.equal?(COPYING)

          next
        end

        copies[source] = COPYING
        pending << [ source, true ]
        if source.is_a?(Hash)
          source.each_pair do |key, item|
            pending << [ item, false ] if container?(item)
            pending << [ key, false ] if container?(key)
          end
        else
          source.each { |item| pending << [ item, false ] if container?(item) }
        end
      end
      copies.fetch(value)
    end
    private_class_method :copy_deep

    def self.snapshot(value, copies) = container?(value) ? copies.fetch(value) : copy_value(value, copies, 0)
    private_class_method :snapshot

    def self.container?(value) = value.is_a?(Hash) || value.is_a?(Array)
    private_class_method :container?
  end
end
