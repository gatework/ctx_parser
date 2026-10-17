# frozen_string_literal: true

require "ctx_parser"
require "json"

# 512 条对应 256 个端口的两类查询，4096 条用于观察扩展成本。
# 输入构造、GC 和正确性校验均不计入耗时；派发使用固定的空结果。
puts RUBY_DESCRIPTION
puts "source=#{CtxParser::Commands.instance_method(:initialize).source_location.first}"
parser = Class.new(CtxParser::Parser) do
  def self.parse(_text, complete:)
    CtxParser::Result.new(status: complete ? :complete : :partial)
  end
end
[ 512, 4096 ].each do |size|
  entries = size.times.map { |index| { dimensions: [ :counters ], command: "show port #{index} counters", parser: parser } }
  expected = entries.map { |entry| entry.fetch(:command) }
  3.times do |trial|
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    declarations = 10.times.map { CtxParser::Commands.new(entries, multi_command: true) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocated = GC.stat(:total_allocated_objects) - allocated
    abort "Command order changed" unless declarations.all? { |commands| commands.by_dimension.fetch(:counters) == expected }
    puts JSON.generate(scenario: "build", commands: size, iterations: 10, trial: trial + 1, seconds: elapsed, allocations: allocated)
  end
  declarations = CtxParser::Commands.new(entries, multi_command: true)
  profile = Class.new(CtxParser::Profile)
  profile.const_set(:COMMANDS, declarations.by_dimension)
  profile.const_set(:PARSERS, declarations.parsers)
  instance = profile.new
  3.times do |trial|
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results = expected.take(128).map { |command| instance.parse(:counters, "", complete: true, command: command) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocated = GC.stat(:total_allocated_objects) - allocated
    abort "Parser selection failed" unless results.all?(&:complete?)
    puts JSON.generate(scenario: "dispatch", commands: size, iterations: results.size, trial: trial + 1, seconds: elapsed, allocations: allocated)
  end
end
