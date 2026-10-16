# frozen_string_literal: true

require_relative "immutable"

module CtxParser
  # 仅保存解析结果；采集命令、时间与证据由调用方管理。
  Result = Data.define(:status, :records, :issues) do
    # 冻结解析状态、归一化记录与诊断证据。
    def initialize(status:, records: [], issues: [])
      raise ArgumentError, "Invalid parser status" unless %i[complete partial failed unsupported].include?(status)
      raise ArgumentError, "Records must be hashes" unless records.is_a?(Array) && records.all? { |row| row.is_a?(Hash) }

      super(status: status, records: Immutable.copy(records), issues: Immutable.copy(issues))
    end

    # 判断解析结果是否具有完整证据。
    def complete? = status == :complete

    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} status=#{status} records=#{records.size}>"
  end
end
