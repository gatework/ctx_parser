# frozen_string_literal: true

require_relative "result"

module CtxParser
  # 同一回显可产生多份清单，各自保留完整性与诊断。
  ResultSet = Data.define(:results) do
    # 冻结具名章节结果，同时保留各章节的独立状态。
    def initialize(results:)
      unless results.is_a?(Hash) && results.any? && results.values.all? { |result| result.is_a?(Result) }
        raise ArgumentError, "Result set must contain parser results"
      end
      super(results: results.dup.freeze)
    end

    # 返回必需的具名章节结果。
    def fetch(name) = results.fetch(name)

    # 判断所有已选事实是否都有完整证据支持。
    def complete? = results.values.all?(&:complete?)

    # 推导汇总状态，避免将证据缺失当作成功。
    def status
      return :complete if complete?
      return :partial if results.values.any? { |result| %i[complete partial].include?(result.status) }

      results.values.all? { |result| result.status == :unsupported } ? :unsupported : :failed
    end

    # 从全部章节结果汇总去重后的诊断。
    def issues = results.values.flat_map(&:issues).uniq

    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} status=#{status} sections=#{results.keys.join(',')}>"
  end
end
