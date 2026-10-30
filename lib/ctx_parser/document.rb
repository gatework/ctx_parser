# frozen_string_literal: true

require_relative "cursor"
require_relative "block"

module CtxParser
  # 持有配置树及诊断；构建器解释语法，Block 只约束来源范围。
  class Document
    attr_reader :cursor, :roots, :issues

    # 使用平台提供的注释及边界规则构建来源文档。
    def initialize(source, comments: nil, boundaries: nil, max_bytes: nil)
      if source.is_a?(Cursor)
        unless max_bytes.nil? || max_bytes.is_a?(Integer) && max_bytes >= 0
          raise ArgumentError, "Invalid byte limit"
        end
        raise ArgumentError, "CLI output exceeds byte limit" if max_bytes && source.content.bytesize > max_bytes
      end
      @cursor = source.is_a?(Cursor) ? source : Cursor.new(source, max_bytes: max_bytes)
      @comments, @boundaries, @issues = comments, boundaries, []
      cursor.rewind
      @roots = validate_roots(build_blocks)
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

    # 默认按缩进构建；原生语法可覆盖此步骤，继续共享来源初始化和校验。
    def build_blocks = Block.read(cursor) { |line| classify(line) }

    # 允许有状态词法分析器将行分类为配置条目、忽略行或边界。
    def classify(line)
      return :boundary if @boundaries&.match?(line.text)
      return :ignored if line.text.empty? || @comments&.match?(line.text)

      :entry
    end

    # 允许词法分析器在文档结束时报告未闭合上下文，不向公共配置块添加词法状态。
    def finish; end

    private

    # 根块可以留出注释或边界行，但不能重叠、倒序或引用别的来源。
    def validate_roots(entries)
      entries = Array.new(entries) if entries.is_a?(Array)
      previous = -1
      unless entries.is_a?(Array) && entries.all? do |entry|
          next false unless entry.is_a?(Block) && entry.cursor.equal?(cursor) && entry.index > previous

          previous = entry.last_index
          true
        end
        raise ArgumentError, "Root blocks must be ordered within this document"
      end
      entries.freeze
    end

    # set 等逐行配置没有缩进父子关系，每行独立保留来源状态。
    class Flat < Document
      protected

      def build_blocks
        entries = []
        while (line = cursor.read)
          case classify(line)
          when :entry then entries << cursor.block(line.index)
          when :ignored, :boundary then cursor.mark(line.index, state: :ignored)
          else raise ArgumentError, "Invalid source line disposition"
          end
        end
        entries
      end
    end
  end
end
