# frozen_string_literal: true

require_relative "command_catalog"

module CtxParser
  # 组合平台命令策略，仅覆盖已确认的型号差异。
  class Profile
    COMMANDS = {}.freeze
    PARSERS = {}.freeze
    MODEL_PARSERS = {}.freeze

    attr_reader :model

    # 根据传入设备型号选择命令与解析行为。
    def initialize(model: nil)
      raise ArgumentError, "Device model must be text" unless model.nil? || model.is_a?(String)

      @model = model&.strip&.downcase&.freeze
      @model_parsers = model_parsers
    end

    # 返回当前平台策略声明的命令目录。
    def commands = self.class::COMMANDS

    # 动态目录可替换解析器索引，同时保留型号特定选择。
    def parsers = self.class::PARSERS

    # 保留选择顺序并归组共享视图，不混用不同命令的正文。
    def queries(names)
      unless names.is_a?(Array) && names.uniq == names && (names - commands.keys).empty?
        raise ArgumentError, "Query dimensions must be unique supported names"
      end

      plan = names.each_with_object({}) do |name, queries|
        commands_for(name).each { |command| (queries[command] ||= []) << name }
      end
      plan.each_value(&:freeze)
      plan.freeze
    end

    # 单个维度可能需要多个独立回显；调用方必须分别保存正文。
    def commands_for(name)
      declaration = commands.fetch(name) { raise ArgumentError, "Unsupported parser dimension" }
      queries = declaration.is_a?(Array) ? declaration : [ declaration ]
      unless queries.any? && queries.uniq == queries && queries.all? { |query| query.is_a?(String) && !query.strip.empty? && !/[\x00-\x1f\x7f]/.match?(query) }
        raise ArgumentError, "Parser dimension must declare one or more unique commands"
      end

      queries.map { |query| query.frozen? ? query : query.dup.freeze }.freeze
    end

    # 解析支持的观测维度对应的命令。
    def command(name)
      queries = commands_for(name)
      raise ArgumentError, "Parser dimension has multiple commands; select one explicitly" unless queries.one?

      queries.first
    end

    # 确定维度使用的解析器，包括命令特定变体。
    def parser_for(name, command: nil)
      query = select_command([ name ], command)
      @model_parsers.fetch(query) { parsers.fetch(query) }
    end

    # 选择目标命令解析器，并投影单个请求维度。
    def parse(name, text, complete: false, command: nil)
      parse_many([ name ], text, complete: complete, command: command).fetch(name)
    end

    # AP、Radio 等共享视图仅解析一次，确保状态与数量证据一致。
    def parse_many(names, text, complete: false, command: nil)
      unless names.is_a?(Array) && names.any? && names.uniq == names
        raise ArgumentError, "Parser dimensions must be a nonempty unique array"
      end
      query = select_command(names, command)

      result = parser_for(names.first, command: query).parse(text, complete: complete)
      names.to_h { |name| [ name, project_independently(name, result) ] }
    end

    private

    # 仅当存在唯一公共查询时允许推断；显式命令必须覆盖全部请求视图。
    def select_command(names, selected)
      candidates = names.map { |name| commands_for(name) }.reduce { |common, queries| common & queries }
      unless selected.nil?
        raise ArgumentError, "Selected command does not provide all parser dimensions" unless candidates.include?(selected)

        selected
      else
        raise ArgumentError, "One CLI output must belong to one command" unless candidates.one?

        candidates.first
      end
    end

    # 采集前校验所选型号，并隔离后续修改对型号查找的影响。
    def model_parsers
      declarations = self.class::MODEL_PARSERS
      raise ArgumentError, "Model parsers must be a hash" unless declarations.is_a?(Hash)

      overrides = declarations.fetch(model, {})
      unless overrides.is_a?(Hash) && overrides.all? do |command, parser|
          self.class::PARSERS.key?(command) && parser.is_a?(Class) && parser < Parser
        end
        raise ArgumentError, "Model parsers must override declared commands with Parser subclasses"
      end

      overrides.dup.freeze
    end

    # 投影失败仅影响单个视图；命令选择及解析错误仍正常抛出。
    def project_independently(name, result)
      return failed_projection(:invalid_parser_result) unless result.is_a?(Result) || result.is_a?(ResultSet)

      projected = project(name, result)
      projected.is_a?(Result) ? projected : failed_projection(:invalid_parser_result)
    rescue KeyError
      code = result.is_a?(ResultSet) && !result.results.key?(name) ? :missing_parser_view : :parser_projection_failed
      failed_projection(code)
    rescue StandardError
      failed_projection(:parser_projection_failed)
    end

    # 诊断代码描述边界失败，不保留异常消息或原始值。
    def failed_projection(code) = Result.new(status: :failed, issues: [ { code: code } ])

    # 从共享命令结果中提取请求维度。
    def project(name, result)
      result.is_a?(ResultSet) ? result.fetch(name) : result
    end
  end
end
