# frozen_string_literal: true

require "ctx_parser"

# 示例仅实现小型语法；厂商语法应放入对应领域 gem。
class ExampleStatusParser < CtxParser::Parser
  private

  # 保留未知行，并遵循调用方声明的传输完整性。
  def parse_output(text, complete:)
    records = []
    issues = []
    text.each_line.with_index(1) do |line, number|
      next if line.strip.empty?

      match = /\A([A-Za-z0-9\/]+) (up|down)\z/.match(line.strip)
      if match
        records << { name: match[1], state: match[2].to_sym }
      else
        issues << { code: :unrecognized_row, line: number }
      end
    end
    status = complete && issues.empty? && !records.empty? ? :complete : :partial
    CtxParser::Result.new(status: status, records: records, issues: issues)
  end
end

result = ExampleStatusParser.parse("Eth1/1 up\nEth1/2 down\n", complete: true)
puts "Parse status: #{result.status}"
result.records.each { |row| puts "#{row[:name]}: #{row[:state]}" }
