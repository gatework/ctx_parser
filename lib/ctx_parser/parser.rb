# frozen_string_literal: true

module CtxParser
  # 提供公共命令解析契约；厂商语法、编码与完整性由子类负责。
  class Parser
    attr_reader :cursor, :blocks, :document

    # 每次调用使用新实例解析，避免共享来源状态。
    def self.parse(text, complete: false)
      new.parse(text, complete: complete)
    end

    # 校验输入及完整性，重置来源状态后执行命令解析器。
    def parse(text, complete: false)
      @document, @cursor, @blocks = nil, nil, [].freeze
      raise ArgumentError, "Runtime output must be text" unless text.is_a?(String)
      raise ArgumentError, "Completeness must be boolean" unless [ true, false ].include?(complete)

      parse_output(text, complete: complete)
    end

    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { parser: self.class.name, cursor: cursor&.as_json, blocks: Array(blocks).size }
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name}>"

    private

    # 每次解析创建私有游标与配置树；序列化结果不包含来源正文。
    def read_configuration(text, comments: nil, boundaries: nil, document_class: Document)
      @document = document_class.new(text, comments: comments, boundaries: boundaries)
      @cursor, @blocks = document.cursor, document.roots
      @blocks
    end

    # 解释当前命令回显，保留不支持或格式错误的证据。
    def parse_output(text, complete:)
      raise NotImplementedError, "Command parsers must implement parse_output"
    end
  end
end

# 在依赖可能触发 Rails 自动加载此命名空间前，先定义基础类。
require_relative "result"
require_relative "result_set"
require_relative "document"
