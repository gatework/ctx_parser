# frozen_string_literal: true

require_relative "ctx_parser/version"

# 加载可能被独立自动加载的依赖前，先定义命名空间。
module CtxParser
end

require_relative "ctx_parser/parser"
if CtxParser.const_defined?(:Parser, false)
  require_relative "ctx_parser/configuration_parser"
  require_relative "ctx_parser/values"
  require_relative "ctx_parser/records"
  require_relative "ctx_parser/command_catalog"
  require_relative "ctx_parser/profile"
  require_relative "ctx_parser/registry"
end
