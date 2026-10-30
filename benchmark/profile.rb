# frozen_string_literal: true

require "ctx_parser"
require "json"

# 动态端口目录在采集前逐条选择实现；同时验证顺序、拒绝未知命令及复用结果。
implementation = Class.new(CtxParser::Parser)
puts RUBY_DESCRIPTION
puts "source=#{CtxParser::Profile.instance_method(:commands_for).source_location.first}"
[ 32, 128, 512, 4096 ].each do |count|
  queries = count.times.map { |index| "show port #{index}".freeze }.freeze
  catalog = CtxParser::Commands.new(queries.map do |query|
    { dimensions: [ :counters ], command: query, parser: implementation }
  end, multi_command: true)
  3.times do |trial|
    profile = CtxParser::Profile.new(declarations: catalog)
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    selected = queries.map { |query| profile.parser_for(:counters, command: query) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat(:total_allocated_objects) - allocations
    abort "Command selection changed" unless selected.size == count && selected.all? { |parser| parser.equal?(implementation) } &&
      profile.commands_for(:counters) == queries
    begin
      profile.parser_for(:counters, command: "show absent")
      abort "Undeclared query accepted"
    rescue ArgumentError
      # 缺失命令须保留原有拒绝契约。
    end
    puts JSON.generate(commands: count, trial: trial + 1, seconds: elapsed, allocations: allocations)
  end
end
