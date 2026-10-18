# frozen_string_literal: true

require "ctx_parser"
require "json"

# 重复封装同一份已冻结事实；输入构造及正确性断言不计入测量。
records = 100_000.times.map { |index| { id: index, name: "port#{index}" } }
source = CtxParser::Result.new(status: :complete, records: records).records
3.times do |trial|
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = CtxParser::Result.new(status: :complete, records: source)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  allocations = GC.stat(:total_allocated_objects) - allocations
  abort "Facts changed" unless result.records.size == 100_000 && result.records.first == { id: 0, name: "port0" } &&
    result.records.last == { id: 99_999, name: "port99999" } && result.records.all?(&:frozen?)
  puts JSON.generate(trial: trial + 1, records: source.size, seconds: elapsed, allocations: allocations)
end
