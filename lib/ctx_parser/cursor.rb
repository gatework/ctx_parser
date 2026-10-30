# frozen_string_literal: true

require "digest"
require_relative "line"
require_relative "capture"
require_relative "input"

module CtxParser
  # 每次解析独立持有游标，区分读取位置、访问状态与语义状态。
  class Cursor
    STATES = %i[pending parsed ignored unsupported invalid].freeze
    RESOLVED_STATES = %i[parsed ignored].freeze

    attr_reader :content, :lines, :checksum, :position

    # 为单次解析创建独立的来源行、语义状态及事实索引。
    def initialize(content, max_bytes: nil)
      raise ArgumentError, "Configuration content must be text" unless content.is_a?(String)

      @content = Input.text(content, encoding: :transcode, max_bytes: max_bytes).freeze

      # scan 直接交付每行，避免同时保留原始行数组与 Line 数组。
      @lines = []
      @content.scan(/[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+\z/) do |raw|
        @lines << Line.new(index: @lines.size, raw: raw.freeze)
      end
      @lines.freeze
      @line_blocks = {}
      @checksum = Digest::SHA256.hexdigest(@content).freeze
      reset!
    end

    # 返回原始来源行数。
    def size = lines.size

    # 单行范围按需复用；回退和重置只改变状态，不改变不可变来源块。
    def block(index)
      validate_index!(index)
      require_relative "block" unless defined?(Block)
      @line_blocks[index] ||= Block.new(cursor: self, header: lines[index], children: [], last_index: index)
    end
    # 判断游标是否到达来源末尾。
    def eof? = position >= size
    # 查看下一来源行，不推进游标也不修改状态。
    def peek = lines[position]
    # 返回来源行处理状态的不可变快照。
    def states = @states.dup.freeze
    # 提供已成功解释的来源行信息。
    def parsed_flags = @states.map { |state| state == :parsed }.freeze
    # 即使采用后序分析，也按文档顺序返回来源，并保留同一行的捕获顺序。
    def captures = @ordered_captures ||= ordered_captures(@captures)

    # 推进游标并记录访问，不代表该行已成功解析。
    def read
      return nil if eof?

      line = peek
      @visited[position] = true
      @position += 1
      line
    end

    # 查找下一待处理行；语义成功或失败仍须由调用方显式记录。
    def read_pending
      while (line = read)
        return line if state(line.index) == :pending
      end
      nil
    end

    # 校验来源行索引后，返回对应语义处理状态。
    def state(index)
      validate_index!(index)
      @states[index]
    end

    # 检查是否解释成功；无效行索引保留 nil。
    def parsed?(index) = valid_index?(index) ? @states[index] == :parsed : nil
    # 独立检查游标是否访问过该行，不与解释成功混淆。
    def visited?(index) = valid_index?(index) ? @visited[index] : nil

    # 查询零起始闭区间的实时解决状态；索引按需延伸，重复查询不再扫描每行。
    def resolved?(first_index, last_index)
      validate_index!(first_index)
      validate_index!(last_index)
      raise ArgumentError, "Source range must be ordered" if first_index > last_index
      return false unless RESOLVED_STATES.include?(@states[first_index])
      return true if first_index == last_index

      @unresolved_prefix ||= [ 0 ]
      while @indexed_states <= last_index
        unresolved = RESOLVED_STATES.include?(@states[@indexed_states]) ? 0 : 1
        @unresolved_prefix[@indexed_states + 1] = @unresolved_prefix[@indexed_states] + unresolved
        @indexed_states += 1
      end
      @unresolved_prefix[last_index + 1] == @unresolved_prefix[first_index]
    end

    # 为有效来源行记录明确的语义状态。
    def mark(index, state: :parsed)
      validate_index!(index)
      raise ArgumentError, "Invalid line state" unless STATES.include?(state)

      # 只有跨越解决/未解决分组才使后缀失效；未查询的来源不承担索引构建成本。
      if index < @indexed_states && RESOLVED_STATES.include?(@states[index]) != RESOLVED_STATES.include?(state)
        @indexed_states = index
      end
      @states[index] = state
      self
    end

    # 返回起点开始下一轮处理，同时保留语义状态与来源证据。
    def rewind
      @position = 0
      self
    end

    # 清空访问、语义状态及捕获事实，重新开始分析。
    def reset!
      @states = Array.new(size, :pending)
      @unresolved_prefix, @indexed_states = nil, 0
      @visited = Array.new(size, false)
      @captures = []
      @captures_by_path, @ordered_by_path = {}, {}
      @ordered_captures = nil
      rewind
    end

    # 回退一行，不改变语义状态。
    def step_back
      return false if position.zero?

      @position -= 1
      true
    end

    # 重新访问前一行，并将其恢复为待解析状态。
    def unread
      return false unless step_back

      mark(position, state: :pending)
      true
    end

    # 将最后消费的行恢复为待解析，不移动游标。
    def defer
      return false if position.zero?

      mark(position - 1, state: :pending)
      true
    end

    # 返回未解决或无效行，排除已明确忽略的注释及领域外配置。
    def unparsed_lines
      lines.reject { |line| RESOLVED_STATES.include?(state(line.index)) }.freeze
    end

    # 拼接未解决来源行，并保留原有格式。
    def unparsed_content = unparsed_lines.map(&:raw).join("").freeze

    # 将事实快照关联到来源块，不将整个块标记为解析成功。
    def capture(block, data:, path:)
      capture_many([ block ], data: data, path: path).first
    end

    # 注册归纳事实的不可变快照前，先校验全部来源。
    def capture_many(blocks, data:, path:)
      require_relative "block" unless defined?(Block)
      blocks = Array.new(blocks) if blocks.is_a?(Array)
      unless blocks.is_a?(Array) && blocks.all? { |block| block.is_a?(Block) && block.cursor.equal?(self) }
        raise ArgumentError, "Blocks must belong to this cursor"
      end

      captured = Capture.for_blocks(blocks, data: data, path: path)
      captured.each do |capture|
        @captures << capture
        (@captures_by_path[capture.path] ||= []) << capture
        @ordered_by_path.delete(capture.path)
      end
      @ordered_captures = nil unless captured.empty?
      captured
    end

    # 使用捕获时的不可变路径作为缓存键，不使用调用方可变查询数组。
    def captures_for(path)
      return @ordered_by_path[path] if @ordered_by_path.key?(path)

      entries = @captures_by_path[path]
      entries ? @ordered_by_path[entries.first.path] = ordered_captures(entries) : [].freeze
    end
    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { position: position, lines: size, states: @states.tally, captures: @captures.size }
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} position=#{position} lines=#{size} captures=#{@captures.size}>"
    alias to_s inspect

    private

    # 同一来源行保持稳定插入顺序，以维持既有来源追溯契约。
    def ordered_captures(entries)
      entries.each_with_index.sort_by { |capture, order| [ capture.block.index, order ] }.map(&:first).freeze
    end

    # 检查整数索引是否属于当前来源文档。
    def valid_index?(index) = index.is_a?(Integer) && index >= 0 && index < size

    # 拒绝指向当前文档之外的行引用。
    def validate_index!(index)
      raise IndexError, "Line index is outside the document" unless valid_index?(index)
    end
  end
end
