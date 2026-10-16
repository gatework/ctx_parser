# frozen_string_literal: true

module CtxParser
  # 消费带分隔符的 CLI 横幅，不将其正文解释为配置。
  class Banner
    # 跟踪横幅分隔符，避免内嵌文本被当作配置。
    def consume(text)
      if @delimiter
        @delimiter = nil if text.include?(@delimiter)
        return true
      end
      match = /\A(?:banner\s+\S+|header\s+\S+(?:\s+information)?)\s+(.+)\z/.match(text)
      return false unless match

      delimiter = match[1].start_with?("^") ? match[1][0, 2] : match[1][0]
      @delimiter = delimiter unless match[1].delete_prefix(delimiter).include?(delimiter)
      true
    end

    # 判断横幅是否仍缺少闭合分隔符。
    def open? = !@delimiter.nil?
  end
end
