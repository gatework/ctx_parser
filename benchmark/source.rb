# frozen_string_literal: true

require "ctx_parser"
require "json"

# 使用合成配置，输入构造与语义断言均不计入测量；无需领域 gem。
text = (1..10_000).map { |index| "interface Ethernet1/#{index}\r\n description port #{index}\n" }.join("")
puts RUBY_DESCRIPTION
puts "source=#{CtxParser::Cursor.instance_method(:initialize).source_location.first}"

[ :cursor, :document ].each do |scenario|
  3.times do |trial|
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    values = 3.times.map do
      scenario == :cursor ? CtxParser::Cursor.new(text) : CtxParser::Document.new(text)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat(:total_allocated_objects) - allocations
    values.each do |value|
      cursor = scenario == :cursor ? value : value.cursor
      abort "Source changed" unless cursor.content == text && cursor.size == 20_000 &&
        cursor.lines.last.text == "description port 10000" && cursor.lines.last.indent == 1
      if scenario == :document
        abort "Tree changed" unless value.roots.size == 10_000 && value.roots.last.children.one? &&
          value.roots.last.content == "interface Ethernet1/10000\r\n description port 10000\n"
      end
    end
    puts JSON.generate(scenario: scenario, trial: trial + 1, lines: 20_000, iterations: 3,
      seconds: elapsed, allocated_objects: allocations)
  end
end
