# frozen_string_literal: true

require_relative "immutable"

module CtxParser
  # 不可变来源行保留原始换行，同时提供用于语法匹配的归一化文本。
  Line = Data.define(:index, :raw) do
    # 保留原始来源文本，并生成索引、正文及缩进信息。
    def initialize(index:, raw:)
      raise ArgumentError, "Line index must be nonnegative" unless index.is_a?(Integer) && index >= 0
      raise ArgumentError, "Line content must be text" unless raw.is_a?(String)

      raw = Immutable.copy_string(raw)
      # strip 已移除行结束空白，避免 chomp 依赖宿主进程的 $/。
      @text = raw.strip.freeze
      @indent = raw[/\A[ \t]*/].size
      super(index: index, raw: raw)
    end

    # 返回诊断使用的从 1 开始的行号。
    def number = index + 1
    # 返回已去除外围缩进和行结束符的来源内容。
    def text = @text
    # 返回构建配置树使用的前导缩进。
    def indent = @indent
    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = { number: number }
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} number=#{number}>"
    alias to_s inspect

    # PP 不得绕过 inspect 暴露来源行。
    def pretty_print(printer) = printer.text(inspect)
  end
end
