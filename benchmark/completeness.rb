# frozen_string_literal: true

require "ctx_parser"
require "json"

# 构造与状态设置不计入耗时；每次查询均校验结果。
puts RUBY_DESCRIPTION
document = CtxParser::Document.new("parent\n" + " child\n" * 2_000)
block = document.roots.first
%i[pending parsed].each do |state|
  document.cursor.size.times { |index| document.cursor.mark(index, state: state) }
  expected = state == :parsed
  3.times do |trial|
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    200.times { abort "Incorrect completeness" unless block.complete? == expected }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat(:total_allocated_objects) - allocations
    puts JSON.generate(state: state, trial: trial + 1, lines: document.cursor.size, queries: 200, seconds: elapsed, allocated_objects: allocations)
  end
end
