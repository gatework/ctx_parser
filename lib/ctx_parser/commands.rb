# frozen_string_literal: true

require_relative "parser"

module CtxParser
  # 每条命令仅声明一次，并派生不可变维度及解析器索引。
  class Commands
    attr_reader :entries, :by_dimension, :parsers

    # 查询文本的唯一值边界；复制后冻结，不冻结调用方提供的字符串。
    def self.command_text(value)
      raise ArgumentError, "One command without control characters is required" unless value.is_a?(String)

      value = String.new(value).freeze
      if value.strip.empty? || /[\x00-\x1f\x7f]/.match?(value)
        raise ArgumentError, "One command without control characters is required"
      end
      value
    end

    # 校验并冻结受支持的维度到命令声明。
    def initialize(entries, multi_command: false)
      unless entries.is_a?(Array)
        raise ArgumentError, "Commands must contain declarations"
      end
      raise ArgumentError, "Multi-command selection must be boolean" unless multi_command == true || multi_command == false

      @multi_command = multi_command
      @by_dimension, @parsers, @entries_by_command = {}, {}, {}
      @entries = Array.new(entries).map! { |entry| register(entry) }.freeze
      @queries = @by_dimension.transform_values { |value| Array(value).freeze }.freeze
      @entries_by_command.freeze
      @by_dimension.freeze
      @parsers.freeze
      freeze
    end

    # 始终返回同一份已校验的查询序列，无需在每个策略实例重新编译。
    def commands_for(name)
      @queries.fetch(name) { raise ArgumentError, "Unsupported parser dimension" }
    end

    # 保留请求与声明顺序；共享命令只计划一次。
    def queries(dimensions)
      validate_dimensions!(dimensions)
      grouped = dimensions.each_with_object({}) do |name, result|
        commands_for(name).each { |command| (result[command] ||= []) << name }
      end
      grouped.each_value(&:freeze)
      grouped.freeze
    end

    # 显式选择通过命令索引核对视图，成本不随整个目录大小增长。
    def select_command(dimensions, command: nil)
      validate_dimensions!(dimensions)
      raise ArgumentError, "Parser dimensions must not be empty" if dimensions.empty?

      unless command.nil?
        raise ArgumentError, "Selected command must be text" unless command.is_a?(String)

        # 只借用输入字节查找，返回目录内已校验的文本，不重复编译或保留调用方行为。
        entry = @entries_by_command[String.new(command)]
        unless entry && dimensions.all? { |name| entry[:dimensions].include?(name) }
          raise ArgumentError, "Selected command does not provide all parser dimensions"
        end
        entry[:command]
      else
        candidates = dimensions.map { |name| commands_for(name) }.reduce { |common, queries| common & queries }
        raise ArgumentError, "One CLI output must belong to one command" unless candidates.one?

        candidates.first
      end
    end

    private

    # 空请求可产生空查询计划；命令选择另行要求至少一个视图。
    def validate_dimensions!(dimensions)
      unless dimensions.is_a?(Array) && (dimensions.size < 2 || dimensions.uniq == dimensions)
        raise ArgumentError, "Query dimensions must be a unique array"
      end
    end

    # 仅复制声明数据；解析器类保留正常 Ruby 生命周期。
    def register(entry)
      unless entry.is_a?(Hash) && entry.size == 3 && %i[dimensions command parser].all? { |key| entry.key?(key) }
        raise ArgumentError, "Command declaration requires dimensions, command and parser"
      end

      dimensions, command, parser = entry.values_at(:dimensions, :command, :parser)
      dimensions = Array.new(dimensions) if dimensions.is_a?(Array)
      unless dimensions.is_a?(Array) && dimensions.any? && dimensions.all? { |name| name.is_a?(Symbol) && !name.empty? } &&
          dimensions.uniq == dimensions && (@multi_command || dimensions.none? { |name| @by_dimension.key?(name) })
        raise ArgumentError, "Command dimensions must be unique nonempty symbols"
      end
      command = self.class.command_text(command)
      raise ArgumentError, "Command is already declared" if @parsers.key?(command)
      raise ArgumentError, "Command parser must inherit from Parser" unless parser.is_a?(Class) && parser < Parser

      dimensions.freeze
      dimensions.each do |name|
        # 索引数组由本实例持有，构建完成后统一冻结；追加不复制已有命令。
        @by_dimension[name] = @by_dimension.key?(name) ? (Array(@by_dimension[name]) << command) : command
      end
      @parsers[command] = parser
      @entries_by_command[command] = { dimensions: dimensions, command: command, parser: parser }.freeze
    end
  end
end
