# frozen_string_literal: true

require "digest"
require "json"
require "baseline"

# 输入构造不计入耗时，并校验每次被测解析的结果。
input = "hostname LEAF\n" + (1..10_000).map do |index|
  "interface Ethernet1/#{index}\n description Test port #{index}\n"
end.join("")
expected = Baseline::CiscoNxos::Parser.parse("hostname LEAF\n", complete: true).to_h
unless expected[:status] == :complete && expected.dig(:records, 0, "facts", "hostname") == "LEAF"
  abort "Unexpected baseline facts"
end

puts RUBY_DESCRIPTION
puts "source=#{Baseline::CiscoNxos::Parser.instance_method(:parse_output).source_location.first}"
puts "result_sha256=#{Digest::SHA256.hexdigest(JSON.generate(expected))}"

# 计时排除输入构造及语义断言；分配量仅统计被测工作。
def measure(name, trial, **details)
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  allocated = GC.stat(:total_allocated_objects) - allocated
  puts JSON.generate(details.merge(scenario: name, trial: trial + 1, seconds: elapsed.round(6), allocated_objects: allocated))
  result
end

3.times do |trial|
  outputs = measure("configuration", trial, input_bytes: input.bytesize, input_lines: input.lines("\n").size, parses: 3) do
    3.times.map { Baseline::CiscoNxos::Parser.parse(input, complete: true).to_h }
  end
  abort "Parsed output changed" unless outputs.all? { |output| output == expected }
end

# 单个归纳事实可对应多条来源命令，每个来源独立保留行范围。
servers = (1..1000).map { |index| "10.0.#{index / 256}.#{index % 256}" }
source = "hostname LEAF\n" + servers.map { |server| "ntp server #{server}\n" }.join("")
3.times do |trial|
  parser = measure("fact_sources", trial, input_bytes: source.bytesize, source_count: servers.size, parses: 1) do
    Baseline::CiscoNxos::Parser.new.tap { |instance| instance.parse(source, complete: true) }
  end
  captures = parser.cursor.captures_for([ "facts", "ntp.servers" ])
  unless captures.size == servers.size && captures.all? { |capture| capture.data == servers } &&
      captures.map(&:line_range) == (2..1001).map { |number| number..number }
    abort "Captured facts or provenance changed"
  end
  puts JSON.generate(scenario: "fact_sources_snapshots", trial: trial + 1,
    distinct_values: captures.map { |capture| capture.data.object_id }.uniq.size, sources: captures.size)
end

# 按报告使用方式查询各来源路径；逆序注册用于验证文档排序。
document = CtxParser::Document.new((1..1000).map { |index| "interface Ethernet1/#{index}\n" }.join(""))
paths = document.roots.map { |block| [ :interfaces, block.text.delete_prefix("interface ") ] }
expected_captures = document.roots.reverse.map do |block|
  document.cursor.capture(block, data: block.text, path: paths[block.index])
end.reverse
3.times do |trial|
  found = measure("source_lookup", trial, source_count: paths.size, lookups: paths.size, repeated: trial.positive?) do
    paths.map { |path| document.cursor.captures_for(path) }
  end
  abort "Source lookup changed" unless found == expected_captures.map { |capture| [ capture ] }
end
