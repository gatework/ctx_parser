# frozen_string_literal: true

require_relative "parser"
require_relative "document"

module CtxParser
  # 共享来源状态与作用域管理；具体解析器负责识别规则及诊断。
  class Configuration < Parser
    attr_reader :cursor, :blocks, :document

    # 新解析开始即清空来源，参数校验失败也不暴露上一次配置。
    def parse(text, complete: false)
      @document, @cursor, @blocks = nil, nil, [].freeze
      @source_path = []
      @invalid_source = @source_error = nil
      super
    end

    # 只展示配置来源元数据，不序列化原文。
    def as_json(*) = super.merge(cursor: cursor&.as_json, blocks: Array(blocks).size)

    private

    # 为新的配置解析建立来源跟踪状态。
    def read_configuration(text, comments: nil, boundaries: nil, document_class: Document)
      @source_path = []
      @invalid_source = @source_error = nil
      @document = document_class.new(text, comments: comments, boundaries: boundaries)
      @cursor, @blocks = document.cursor, document.roots
      @blocks
    end

    # 仅在解释成功后标记来源行；嵌套转换失败归因到最内层来源。
    def analyze(block)
      validate_source!(block)
      analyze_source(block) { yield }
    end

    # 来源参数错误不进入语义异常处理，避免污染当前文档或遮盖原异常。
    def analyze_source(block)
      value = yield
      cursor.mark(block.index, state: :parsed) if cursor.state(block.index) == :pending
      if cursor.state(block.index) == :parsed
        block.children.each { |child| unparsed_child(child) if cursor.state(child.index) == :pending }
      end
      value
    rescue ArgumentError => error
      # 同一异常向外传播时仅保留最内层出错块，避免把整个父配置误标为无效。
      unless @source_error.equal?(error)
        @source_error, @invalid_source = error, block
      end
      if block.equal?(@invalid_source)
        cursor.mark(block.index, state: :invalid)
      elsif cursor.state(block.index) == :pending
        cursor.mark(block.index, state: :parsed)
      end
      raise
    end

    # 各子节点独立保留来源状态及错误位置。
    def analyze_children(block, &operation)
      validate_source!(block)
      block.children.each { |child| analyze(child) { operation.call(child) } }
    end

    # 进入临时结果路径，成功或失败后均恢复父作用域。
    def scope(block, path)
      previous_path = @source_path
      validate_source!(block)
      path = Capture.path_snapshot(path)
      @source_path = path
      value = yield
      capture(block, value, path)
      value
    ensure
      @source_path = previous_path
    end

    # 将归一化事实关联到来源块及结果路径。
    def capture(block, value, path)
      cursor.capture(block, data: value, path: path)
    end

    # 迭代忽略领域外子树，不宣称其产生已解析事实。
    def ignore(block)
      validate_source!(block)
      pending = [ block ]
      until pending.empty?
        entry = pending.pop
        cursor.mark(entry.index, state: :ignored)
        pending.concat(entry.children)
      end
      nil
    end

    # 每次分析只接受当前文档的来源块，校验必须早于外部回调。
    def validate_source!(block)
      unless block.is_a?(Block) && block.cursor.equal?(cursor)
        raise ArgumentError, "Source block must belong to this cursor"
      end
    end

    # 未处理的子节点保持待解析；具体解析器可诊断位置错误的相关命令。
    def unparsed_child(_block); end
  end
end
