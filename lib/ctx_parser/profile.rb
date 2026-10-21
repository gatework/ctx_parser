# frozen_string_literal: true

require_relative "commands"

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
      @model_parsers = model_parser_overrides
      cache_commands(self.class::COMMANDS, strict: true)
    end

    # 注册时核对静态目录；动态实例仍在实际查询时重新校验。
    def self.validate_declarations!
      directory, implementations = self::COMMANDS, self::PARSERS
      unless directory.is_a?(Hash) && implementations.is_a?(Hash) &&
          directory.keys.all? { |name| name.is_a?(Symbol) && !name.empty? }
        raise ArgumentError, "Profile commands and parsers must be named mappings"
      end

      queries = directory.values.flat_map do |value|
        entries = value.is_a?(Array) ? value : [ value ]
        unless entries.any? && entries.uniq == entries && entries.all? { |entry| valid_command?(entry) }
          raise ArgumentError, "Parser dimension must declare one or more unique commands"
        end
        entries
      end.uniq
      unless (queries - implementations.keys).empty? && (implementations.keys - queries).empty? &&
          implementations.values.all? { |parser| parser.is_a?(Class) && parser < Parser }
        raise ArgumentError, "Profile commands must match Parser implementations"
      end
      normalized_model_parsers
      true
    end

    # 校验静态目录中的单命令文本，不接受控制字符。
    def self.valid_command?(value)
      value.is_a?(String) && !value.strip.empty? && !/[\x00-\x1f\x7f]/.match?(value)
    end
    private_class_method :valid_command?

    # 返回当前平台策略声明的命令目录。
    def commands = self.class::COMMANDS

    # 动态目录可替换解析器索引，同时保留型号特定选择。
    def parsers = self.class::PARSERS

    # 保留选择顺序并归组共享视图，不混用不同命令的正文。
    def queries(dimensions)
      unless dimensions.is_a?(Array) && dimensions.uniq == dimensions && (dimensions - commands.keys).empty?
        raise ArgumentError, "Query dimensions must be unique supported names"
      end

      dimensions_by_command = dimensions.each_with_object({}) do |name, queries|
        commands_for(name).each { |command| (queries[command] ||= []) << name }
      end
      dimensions_by_command.each_value(&:freeze)
      dimensions_by_command.freeze
    end

    # 单个维度可能需要多个独立回显；调用方必须分别保存正文。
    def commands_for(name)
      directory = commands
      declaration = directory.fetch(name) { raise ArgumentError, "Unsupported parser dimension" }
      cached = cache_commands(directory)
      return cached[:queries].fetch(name) if cached

      validated_queries(declaration)
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
      implementation_for(query)
    end

    # 选择目标命令解析器，并投影单个请求维度。
    def parse(name, text, complete: false, command: nil)
      parse_many([ name ], text, complete: complete, command: command).fetch(name)
    end

    # AP、Radio 等共享视图仅解析一次，确保状态与数量证据一致。
    def parse_many(dimensions, text, complete: false, command: nil)
      unless dimensions.is_a?(Array) && dimensions.any? && dimensions.uniq == dimensions
        raise ArgumentError, "Parser dimensions must be a nonempty unique array"
      end
      # 扩展解析器可调用外部代码；结果投影始终使用入口处的请求。
      dimensions = dimensions.dup.freeze
      query = select_command(dimensions, command)

      # 查询已覆盖全部请求维度，无需再次遍历第一个维度的完整命令列表。
      result = implementation_for(query).parse(text, complete: complete)
      dimensions.to_h { |name| [ name, project_independently(name, result) ] }
    end

    private

    # 发现阶段可替换实例目录；只缓存当前深冻结目录，不继承旧目录的选择结果。
    def cache_commands(directory, strict: false)
      cached = @command_cache
      return cached if cached && directory.equal?(cached[:directory])
      return if frozen?

      queries = compile_commands(directory)
      return unless queries

      membership = queries.transform_values { |entries| entries.to_h { |query| [ query, true ] }.freeze }.freeze
      # 一次发布完整索引；并发查找只读取自己取得的快照，不混合两份目录。
      @command_cache = { directory: directory, queries: queries, membership: membership }.freeze
    rescue ArgumentError
      # 动态目录仍按请求维度报错，未使用的无效声明不能阻断其他维度。
      raise if strict

      nil
    end

    # 可变容器或文本仍逐次校验；普通深冻结目录允许共享验证后的顺序与成员索引。
    def compile_commands(directory)
      return unless directory.instance_of?(Hash) && directory.frozen? && !directory.compare_by_identity? &&
          directory.keys.all? { |name| name.is_a?(Symbol) && !name.empty? } && directory.values.all? do |value|
        entries = value.is_a?(Array) ? value : [ value ]
        (!value.is_a?(Array) || value.instance_of?(Array) && value.frozen?) &&
          entries.all? { |query| query.instance_of?(String) && query.frozen? }
      end

      directory.to_h { |name, declaration| [ name, validated_queries(declaration) ] }.freeze
    end

    # 查询快照不冻结调用方的数组或字符串。
    def validated_queries(declaration)
      queries = declaration.is_a?(Array) ? declaration : [ declaration ]
      unless queries.any? && queries.uniq == queries && queries.all? { |query| query.is_a?(String) && !query.strip.empty? && !/[\x00-\x1f\x7f]/.match?(query) }
        raise ArgumentError, "Parser dimension must declare one or more unique commands"
      end

      queries.map { |query| query.frozen? ? query : query.dup.freeze }.freeze
    end

    # 仅当存在唯一公共查询时允许推断；显式命令必须覆盖全部请求视图。
    def select_command(dimensions, selected)
      declarations = dimensions.map do |name|
        queries = commands_for(name)
        cached = @command_cache
        membership = cached[:membership][name] if cached && queries.equal?(cached[:queries][name])
        [ queries, membership ]
      end
      if selected.nil?
        candidates = declarations.map(&:first).reduce { |common, queries| common & queries }
        raise ArgumentError, "One CLI output must belong to one command" unless candidates.one?

        candidates.first
      else
        supported = declarations.all? do |queries, membership|
          if selected.instance_of?(String) && membership
            membership.key?(selected)
          else
            queries.include?(selected)
          end
        end
        raise ArgumentError, "Selected command does not provide all parser dimensions" unless supported

        selected
      end
    end

    # 采集前校验所选型号，并隔离后续修改对型号查找的影响。
    def self.normalized_model_parsers
      declarations = self::MODEL_PARSERS
      raise ArgumentError, "Model parsers must be a hash" unless declarations.is_a?(Hash)

      normalized = {}
      declarations.each do |name, overrides|
        unless name.nil? || name.is_a?(String) && !name.strip.empty?
          raise ArgumentError, "Model parser keys must be device model names"
        end
        key = name&.strip&.downcase
        raise ArgumentError, "Model parser names must be unique after normalization" if normalized.key?(key)
        unless overrides.is_a?(Hash) && overrides.all? do |command, parser|
            self::PARSERS.key?(command) && parser.is_a?(Class) && parser < Parser
          end
          raise ArgumentError, "Model parsers must override declared commands with Parser subclasses"
        end
        normalized[key] = overrides
      end

      normalized
    end
    private_class_method :normalized_model_parsers

    # 注册与实例选择共用声明校验，所选覆盖仍独立于后续调用方修改。
    def model_parser_overrides
      self.class.send(:normalized_model_parsers).fetch(model, {}).dup.freeze
    end

    # 动态目录的错误仍在调用边界报告，不暴露底层 Hash 的 KeyError。
    def implementation_for(query)
      implementation = @model_parsers.fetch(query) { parsers.fetch(query) { raise ArgumentError, "Missing command parser" } }
      unless implementation.is_a?(Class) && implementation < Parser
        raise ArgumentError, "Command parser must inherit from Parser"
      end
      implementation
    end

    # 投影失败仅影响单个视图；命令选择及解析错误仍正常抛出。
    def project_independently(name, result)
      return failed_projection(:invalid_parser_result) unless result.is_a?(Result) || result.is_a?(Results)

      projected = project(name, result)
      projected.is_a?(Result) ? projected : failed_projection(:invalid_parser_result)
    rescue KeyError
      code = result.is_a?(Results) && !result.key?(name) ? :missing_parser_view : :parser_projection_failed
      failed_projection(code)
    rescue StandardError
      failed_projection(:parser_projection_failed)
    end

    # 诊断代码描述边界失败，不保留异常消息或原始值。
    def failed_projection(code) = Result.new(status: :failed, issues: [ { code: code } ])

    # 从共享命令结果中提取请求维度。
    def project(name, result)
      result.is_a?(Results) ? result.fetch(name) : result
    end
  end
end
