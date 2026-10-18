# frozen_string_literal: true

require_relative "cursor"

module CtxParser
  # 配置节点覆盖整个子树，保留未知命令、空白及原始换行。
  class Block
    Draft = Struct.new(:header, :children, :last_index)
    private_constant :Draft

    attr_reader :cursor, :header, :children, :last_index

    # 冻结已校验的来源范围及其子配置块。
    def initialize(cursor:, header:, children:, last_index:)
      unless cursor.is_a?(Cursor) && header.is_a?(Line) && cursor.lines[header.index].equal?(header) && last_index.is_a?(Integer) &&
          (header.index...cursor.size).cover?(last_index)
        raise ArgumentError, "Invalid source block range"
      end

      previous_index = header.index
      unless children.is_a?(Array) && children.all? do |child|
          next false unless child.is_a?(Block) && child.cursor.equal?(cursor) &&
            child.index > previous_index && child.last_index <= last_index && child.header.indent > header.indent

          previous_index = child.last_index
          true
        end
        raise ArgumentError, "Child blocks must be ordered within their parent source"
      end

      @cursor, @header, @last_index = cursor, header, last_index
      @children = children.dup.freeze
      freeze
    end

    # 构建缩进结构，同时由调用方根据当前词法状态分类来源行。
    def self.read(cursor, comments: nil, boundaries: nil)
      roots, stack = [], []
      while (line = cursor.read)
        disposition = if block_given?
          yield line
        elsif boundaries&.match?(line.text)
          :boundary
        elsif line.text.empty? || comments&.match?(line.text)
          :ignored
        else
          :entry
        end
        case disposition
        when :boundary
          stack.pop.last_index = line.index - 1 until stack.empty?
          cursor.mark(line.index, state: :ignored)
        when :ignored
          cursor.mark(line.index, state: :ignored)
        when :entry
          while stack.any? && line.indent <= stack.last.header.indent
            stack.pop.last_index = line.index - 1
          end
          draft = Draft.new(line, [], nil)
          (stack.last&.children || roots) << draft
          stack << draft
        else
          raise ArgumentError, "Invalid source line disposition"
        end
      end
      stack.pop.last_index = cursor.position - 1 until stack.empty?
      roots.map { |draft| build(cursor, draft) }.freeze
    end

    # 迭代冻结配置块树，不依赖 Ruby 递归深度。
    def self.build(cursor, draft)
      # 使用显式栈先构建子节点再构建父节点，保留顺序并避免递归栈增长。
      stack = [ [ draft, 0, [] ] ]
      until stack.empty?
        entry, next_child, children = stack.last
        if (child = entry.children[next_child])
          stack.last[1] += 1
          stack << [ child, 0, [] ]
        else
          block = new(cursor: cursor, header: entry.header, last_index: entry.last_index, children: children)
          stack.pop
          return block if stack.empty?

          stack.last[2] << block
        end
      end
    end
    private_class_method :build

    # 返回配置块标题的零起始索引。
    def index = header.index
    # 返回配置块标题从 1 开始的来源行号。
    def line = header.number
    # 返回已去除外围缩进和行结束符的来源内容。
    def text = header.text
    # 返回配置块或捕获事实覆盖的闭合来源区间。
    def line_range = line..(last_index + 1)
    # 返回属于当前配置块的原始来源行。
    def lines = cursor.lines[index..last_index].freeze
    # 返回配置块或捕获事实对应的精确来源文本。
    def content = lines.map(&:raw).join("").freeze
    # 返回当前配置块各来源行的处理状态。
    def states = lines.map { |source| cursor.state(source.index) }.freeze
    # 要求块内所有来源行均已解析或明确忽略。
    def complete? = (index..last_index).all? { |index| Cursor::RESOLVED_STATES.include?(cursor.state(index)) }
    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { first_line: line, last_line: last_index + 1, children: children.size }
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} lines=#{line_range} children=#{children.size}>"
    alias to_s inspect
  end
end
