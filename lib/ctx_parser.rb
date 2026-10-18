# frozen_string_literal: true

require_relative "ctx_parser/version"

# 加载可能被独立自动加载的依赖前，先定义命名空间。
module CtxParser
end

require_relative "ctx_parser/parser"
# 直接加载 parser 时，命名空间 autoload 可能重入此入口；此时 Parser 尚未定义。
if CtxParser.const_defined?(:Parser, false)
  require_relative "ctx_parser/configuration"
  require_relative "ctx_parser/values"
  require_relative "ctx_parser/records"
  require_relative "ctx_parser/commands"
  require_relative "ctx_parser/profile"
  require_relative "ctx_parser/registry"
  require_relative "ctx_parser/banner"
end
