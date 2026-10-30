# frozen_string_literal: true

require_relative "immutable"

module CtxParser
  # 保存不可变事实及其来源；路径相对于首条配置结果记录。
  class Capture
    Snapshot = Data.define(:data, :path) do
      # 此边界仅接收调用方原始数据，各快照自行持有深度冻结的副本。
      def initialize(data:, path:)
        super(data: Immutable.copy(data), path: Capture.path_snapshot(path))
      end
    end
    private_constant :Snapshot

    attr_reader :block, :data, :path

    # 作用域进入前与事实捕获时共用路径边界，不保留调用方可变键。
    def self.path_snapshot(path)
      unless path.is_a?(Array) && path.all? { |key| key.nil? || key.is_a?(Symbol) || key.is_a?(String) || key.is_a?(Integer) }
        raise ArgumentError, "Capture path must contain record keys or indexes"
      end

      Immutable.copy(path)
    end

    # 冻结解析事实及其来源块和结果路径。
    def initialize(block:, data:, path:)
      require_relative "block" unless defined?(Block)
      raise ArgumentError, "Capture source must be a block" unless block.is_a?(Block)

      initialize_snapshot(block, Snapshot.new(data: data, path: path))
    end

    # 同一事实的多个来源共享已复制的值，不共享未经校验的调用方容器。
    def self.for_blocks(blocks, data:, path:)
      require_relative "block" unless defined?(Block)
      blocks = Array.new(blocks) if blocks.is_a?(Array)
      unless blocks.is_a?(Array) && blocks.all? { |block| block.is_a?(Block) }
        raise ArgumentError, "Capture sources must be blocks"
      end
      return [].freeze if blocks.empty?

      snapshot = Snapshot.new(data: data, path: path)
      blocks.map! { |block| allocate.tap { |capture| capture.send(:initialize_snapshot, block, snapshot) } }.freeze
    end

    # 返回配置块或捕获事实对应的精确来源文本。
    def content = block.content
    # 返回配置块或捕获事实覆盖的闭合来源区间。
    def line_range = block.line_range
    # 判断捕获事实依赖的所有来源行是否均已解决。
    def complete? = block.complete?
    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { first_line: line_range.begin, last_line: line_range.end, complete: complete? }
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} lines=#{line_range}>"
    alias to_s inspect

    private

    # 私有工厂仅接收由本类完成复制及校验的快照。
    def initialize_snapshot(block, snapshot)
      @block, @data, @path = block, snapshot.data, snapshot.path
      freeze
    end
  end
end
