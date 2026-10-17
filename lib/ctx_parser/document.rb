# frozen_string_literal: true

require_relative "cursor"
require_relative "block"

module CtxParser
  # 持有配置树及诊断；分类器负责语法，Block 负责缩进范围。
  class Document
    attr_reader :cursor, :roots, :issues

    # 使用平台提供的注释及边界规则构建来源文档。
    def initialize(source, comments: nil, boundaries: nil)
      @cursor = source.is_a?(Cursor) ? source : Cursor.new(source)
      @comments, @boundaries, @issues = comments, boundaries, []
      @roots = Block.read(cursor) { |line| classify(line) }
      finish
      @issues = Immutable.copy(@issues)
    end

    # 选择符合目标命令语法的根配置块。
    def sections(pattern) = roots.select { |entry| pattern.match?(entry.text) }
    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { sections: roots.size, issues: issues.size, cursor: cursor.as_json }
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} sections=#{roots.size} issues=#{issues.size}>"
    alias to_s inspect

    protected

    # 允许有状态词法分析器将行分类为配置条目、忽略行或边界。
    def classify(line)
      return :boundary if @boundaries&.match?(line.text)
      return :ignored if line.text.empty? || @comments&.match?(line.text)

      :entry
    end

    # 允许词法分析器在文档结束时报告未闭合上下文，不向公共配置块添加词法状态。
    def finish; end
  end
end
