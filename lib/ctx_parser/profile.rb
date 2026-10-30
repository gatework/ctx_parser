# frozen_string_literal: true

require_relative "commands"

module CtxParser
  # 组合一份不可变命令声明、型号选择与独立视图投影。
  class Profile
    DECLARATIONS = Commands.new([])
    MODEL_PARSERS = {}.freeze

    attr_reader :model, :declarations

    # 静态与发现目录使用同一边界；每个实例持有完整声明快照。
    def initialize(model: nil, declarations: self.class::DECLARATIONS)
      raise ArgumentError, "Device model must be text" unless model.nil? || model.is_a?(String)

      @model = model && String.new(model).strip.downcase.freeze
      @model_parsers = self.class.send(:normalized_model_parsers, declarations).fetch(@model, {}.freeze)
      @declarations = declarations
    end

    # 复制策略实例后一次替换声明；校验失败不影响原实例或型号覆盖。
    def with_declarations(declarations)
      raise ArgumentError, "Profile declarations must be Commands" unless declarations.is_a?(Commands)
      unless @model_parsers.each_key.all? { |command| declarations.parsers.key?(command) }
        raise ArgumentError, "Model parsers must override declared commands"
      end

      dup.tap { |copy| copy.replace_declarations(declarations) }
    end

    # 注册与实例创建共同校验目录和全部型号覆盖，拒绝旧的双目录声明。
    def self.validate_declarations!(declarations = self::DECLARATIONS)
      normalized_model_parsers(declarations)
      true
    end

    # 型号目录在实例创建时快照；后续派生实例继承已经选定的覆盖。
    def self.normalized_model_parsers(declarations)
      owners = ancestors.take_while { |ancestor| ancestor != Object }
      if owners.any? { |owner| owner.const_defined?(:COMMANDS, false) || owner.const_defined?(:PARSERS, false) }
        raise ArgumentError, "Declare Commands through DECLARATIONS instead of COMMANDS/PARSERS"
      end
      raise ArgumentError, "Profile declarations must be Commands" unless declarations.is_a?(Commands)
      raise ArgumentError, "Model parsers must be a hash" unless self::MODEL_PARSERS.is_a?(Hash)

      normalized = {}
      self::MODEL_PARSERS.each do |name, overrides|
        unless name.nil? || name.is_a?(String) && !name.strip.empty?
          raise ArgumentError, "Model parser keys must be device model names"
        end
        key = name && String.new(name).strip.downcase.freeze
        raise ArgumentError, "Model parser names must be unique after normalization" if normalized.key?(key)
        unless overrides.is_a?(Hash) && overrides.all? do |command, parser|
            declarations.parsers.key?(command) && parser.is_a?(Class) && parser < Parser
          end
          raise ArgumentError, "Model parsers must override declared commands with Parser subclasses"
        end
        normalized[key] = overrides.to_h { |command, parser| [ Commands.command_text(command), parser ] }.freeze
      end
      normalized.freeze
    end
    private_class_method :normalized_model_parsers

    # 只读索引是声明的投影，不作为独立扩展入口。
    def commands = declarations.by_dimension
    def parsers = declarations.parsers
    def queries(dimensions) = declarations.queries(dimensions)
    def commands_for(name) = declarations.commands_for(name)

    # 单维度仍可能需要多条命令；只允许唯一命令隐式选择。
    def command(name)
      queries = commands_for(name)
      raise ArgumentError, "Parser dimension has multiple commands; select one explicitly" unless queries.one?

      queries.first
    end

    # 命令及其实现从同一份目录读取，再应用已校验的型号覆盖。
    def parser_for(name, command: nil)
      catalog = declarations
      query = catalog.select_command([ name ], command: command)
      @model_parsers.fetch(query) { catalog.parsers.fetch(query) }
    end

    # 选择目标命令解析器，并投影单个请求维度。
    def parse(name, text, complete: false, command: nil)
      parse_many([ name ], text, complete: complete, command: command).fetch(name)
    end

    # 共享视图仅解析一次，扩展回调不能改变已经固定的请求或目录。
    def parse_many(dimensions, text, complete: false, command: nil)
      dimensions = Array.new(dimensions) if dimensions.is_a?(Array)
      unless dimensions.is_a?(Array) && dimensions.any? && dimensions.uniq == dimensions
        raise ArgumentError, "Parser dimensions must be a nonempty unique array"
      end
      dimensions.freeze
      catalog = declarations
      query = catalog.select_command(dimensions, command: command)
      implementation = @model_parsers.fetch(query) { catalog.parsers.fetch(query) }
      result = implementation.parse(text, complete: complete)
      dimensions.to_h { |name| [ name, project_independently(name, result) ] }
    end

    protected

    # 仅在副本上安装已经校验的完整目录，不重跑子类初始化。
    def replace_declarations(declarations) = @declarations = declarations

    private

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
