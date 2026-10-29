# frozen_string_literal: true

require_relative "parser"

module CtxParser
  # 每条命令仅声明一次，并派生不可变维度及解析器索引。
  class Commands
    attr_reader :entries, :by_dimension, :parsers

    # 查询文本的唯一值边界；复制后冻结，不冻结调用方提供的字符串。
    def self.command_text(value)
      unless value.is_a?(String) && !value.strip.empty? && !/[\x00-\x1f\x7f]/.match?(value)
        raise ArgumentError, "One command without control characters is required"
      end
      value.frozen? ? value : value.dup.freeze
    end

    # 校验并冻结受支持的维度到命令声明。
    def initialize(entries, multi_command: false)
      unless entries.is_a?(Array) && entries.any?
        raise ArgumentError, "Commands must contain declarations"
      end
      raise ArgumentError, "Multi-command selection must be boolean" unless multi_command == true || multi_command == false

      @multi_command = multi_command
      @by_dimension, @parsers = {}, {}
      @entries = entries.map { |entry| register(entry) }.freeze
      @by_dimension.each_value { |value| value.freeze }
      @by_dimension.freeze
      @parsers.freeze
      freeze
    end

    private

    # 仅复制声明数据；解析器类保留正常 Ruby 生命周期。
    def register(entry)
      unless entry.is_a?(Hash) && entry.size == 3 && %i[dimensions command parser].all? { |key| entry.key?(key) }
        raise ArgumentError, "Command declaration requires dimensions, command and parser"
      end

      dimensions, command, parser = entry.values_at(:dimensions, :command, :parser)
      unless dimensions.is_a?(Array) && dimensions.any? && dimensions.all? { |name| name.is_a?(Symbol) && !name.empty? } &&
          dimensions.uniq == dimensions && (@multi_command || dimensions.none? { |name| @by_dimension.key?(name) })
        raise ArgumentError, "Command dimensions must be unique nonempty symbols"
      end
      command = self.class.command_text(command)
      raise ArgumentError, "Command is already declared" if @parsers.key?(command)
      raise ArgumentError, "Command parser must inherit from Parser" unless parser.is_a?(Class) && parser < Parser

      dimensions = dimensions.dup.freeze
      dimensions.each do |name|
        # 索引数组由本实例持有，构建完成后统一冻结；追加不复制已有命令。
        @by_dimension[name] = @by_dimension.key?(name) ? (Array(@by_dimension[name]) << command) : command
      end
      @parsers[command] = parser
      { dimensions: dimensions, command: command, parser: parser }.freeze
    end
  end
end
