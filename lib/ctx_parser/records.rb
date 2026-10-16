# frozen_string_literal: true

module CtxParser
  # 检测身份冲突，不附加厂商特定的保留或完整性策略。
  class Records
    attr_reader :rows, :first_occurrences, :unambiguous, :duplicate_identity_count, :duplicate_row_count

    # 冻结筛选结果数组，记录值的所有权仍属于调用方。
    def initialize(rows, identity: nil, &key)
      unless rows.is_a?(Array) && rows.all? { |row| row.is_a?(Hash) }
        raise ArgumentError, "Records must be hashes"
      end

      key ||= identity if identity.respond_to?(:call)
      key ||= ->(row) { row.values_at(*identity) } if identity.is_a?(Array) && identity.any?
      raise ArgumentError, "Identity must be a nonempty array or callable" unless key

      @rows = rows.dup.freeze
      groups = @rows.group_by { |row| key.call(row) }.values
      @first_occurrences = groups.map(&:first).freeze
      @unambiguous = groups.filter_map { |group| group.first if group.one? }.freeze
      @duplicate_identity_count = groups.count { |group| group.size > 1 }
      @duplicate_row_count = @rows.size - groups.size
      freeze
    end

    # 判断是否有多条记录声明相同逻辑身份。
    def duplicates? = duplicate_identity_count.positive?
    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { rows: rows.size, duplicate_identities: duplicate_identity_count }

    # 提供身份统计，不记录可能包含敏感信息的记录正文。
    def inspect = "#<#{self.class.name} size=#{rows.size} duplicate_identities=#{duplicate_identity_count}>"
    alias to_s inspect
  end
end
