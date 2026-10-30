# frozen_string_literal: true

module CtxParser
  # 检测身份冲突，不附加厂商特定的保留或完整性策略。
  class Records
    attr_reader :rows, :first_occurrences, :unambiguous, :duplicate_identity_count, :duplicate_row_count

    # 冻结筛选结果数组，记录值的所有权仍属于调用方。
    def initialize(rows, identity: nil, &identity_key)
      rows = Array.new(rows) if rows.is_a?(Array)
      unless rows.is_a?(Array) && rows.all? { |row| row.is_a?(Hash) }
        raise ArgumentError, "Records must be hashes"
      end

      identity_key ||= identity if identity.respond_to?(:call)
      identity_key ||= ->(row) { row.values_at(*identity) } if identity.is_a?(Array) && identity.any?
      raise ArgumentError, "Identity must be a nonempty array or callable" unless identity_key

      @rows = rows.freeze
      positions = {}
      first_occurrences, unambiguous = [], []
      @duplicate_identity_count = 0
      @rows.each do |row|
        key = identity_key.call(row)
        if (position = positions[key])
          @duplicate_identity_count += 1 if unambiguous[position]
          unambiguous[position] = nil
        else
          positions[key] = first_occurrences.size
          first_occurrences << row
          unambiguous << row
        end
      end
      @first_occurrences = first_occurrences.freeze
      @unambiguous = unambiguous.compact.freeze
      @duplicate_row_count = @rows.size - first_occurrences.size
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
