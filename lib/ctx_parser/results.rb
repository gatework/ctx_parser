# frozen_string_literal: true

require_relative "result"

module CtxParser
  # 同一回显可产生多份清单，各自保留完整性与诊断。
  Results = Data.define(:by_dimension) do
    # 冻结具名章节结果，同时保留各章节的独立状态。
    def initialize(by_dimension:)
      unless by_dimension.is_a?(Hash) && by_dimension.any? &&
          by_dimension.keys.all? { |name| name.is_a?(Symbol) && !name.empty? } &&
          by_dimension.values.all? { |result| result.is_a?(Result) }
        raise ArgumentError, "Results must map named dimensions to parser results"
      end
      # 普通映射不继承调用方的默认值或默认回调，缺失维度必须仍然缺失。
      super(by_dimension: by_dimension.to_h { |name, result| [ name, result ] }.freeze)
    end

    # 返回必需的具名章节结果。
    def fetch(name) = by_dimension.fetch(name)

    # 只查询明确提供的维度，不把缺失结果当作空清单。
    def key?(name) = by_dimension.key?(name)

    # 判断所有已选事实是否都有完整证据支持。
    def complete? = by_dimension.each_value.all?(&:complete?)

    # 推导汇总状态，避免将证据缺失当作成功。
    def status
      return :complete if complete?
      return :partial if by_dimension.each_value.any? { |result| %i[complete partial].include?(result.status) }

      by_dimension.each_value.all? { |result| result.status == :unsupported } ? :unsupported : :failed
    end

    # 从全部章节结果汇总去重后的诊断。
    def issues = by_dimension.each_value.flat_map(&:issues).uniq

    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} status=#{status} dimensions=#{by_dimension.keys.join(',')}>"
    alias to_s inspect
  end
end
