# frozen_string_literal: true

module CtxParser
  # 按显式编码、NUL 和大小策略归一化输入字节及换行。
  module Input
    module_function

    # 校验来源文本，仅按请求调整编码或换行形式。
    def text(content, encoding: :preserve, newlines: :preserve, allow_nul: false, max_bytes: nil)
      raise ArgumentError, "CLI output must be text" unless content.is_a?(String)
      raise ArgumentError, "Invalid encoding policy" unless %i[preserve utf8 transcode].include?(encoding)
      raise ArgumentError, "Invalid newline policy" unless %i[preserve lf delete_cr].include?(newlines)
      raise ArgumentError, "NUL policy must be boolean" unless [ true, false ].include?(allow_nul)
      raise ArgumentError, "Invalid byte limit" unless max_bytes.nil? || (max_bytes.is_a?(Integer) && max_bytes >= 0)
      raise ArgumentError, "CLI output exceeds byte limit" if max_bytes && content.bytesize > max_bytes

      value = content.dup
      value.force_encoding(Encoding::UTF_8) if encoding == :utf8 || value.encoding == Encoding::BINARY
      raise EncodingError, "CLI output encoding is invalid" unless value.valid_encoding?

      value = value.encode(Encoding::UTF_8) if encoding == :transcode
      raise ArgumentError, "CLI output contains a NUL byte" if !allow_nul && value.include?("\0")

      case newlines
      when :lf then value.gsub(/\r\n?/, "\n")
      when :delete_cr then value.delete("\r")
      else value
      end
    end
  end
end
