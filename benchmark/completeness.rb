# frozen_string_literal: true

require "ctx_parser"
require "json"
require "objspace"

# 同一入口可通过 -I 加载基线与候选；构造、初始标记和结果验证不计入测量。
library = File.dirname(CtxParser::Cursor.instance_method(:state).source_location.first)
digest = Digest::SHA256.hexdigest(Dir[File.join(library, "*.rb")].sort.map { |path| File.binread(path) }.join(""))
puts JSON.generate(ruby: RUBY_DESCRIPTION, library: library, source_sha256: digest)

%i[first stable pending single small_range alternating_tail alternating_head mark_only deep].each do |scenario|
  3.times do |trial|
    size = scenario == :deep ? 500 : 10_001
    text = scenario == :deep ? size.times.map { |index| "#{' ' * index}entry\n" }.join("") : "parent\n" + " child\n" * (size - 1)
    document = CtxParser::Document.new(text)
    cursor = document.cursor
    size.times { |index| cursor.mark(index) } unless scenario == :pending
    block = document.roots.first
    block = block.children.first if scenario == :single
    block = CtxParser::Block.new(cursor: cursor, header: cursor.lines.first, children: [], last_index: 16) if scenario == :small_range
    nodes = []
    if scenario == :deep
      node = block
      while node
        nodes << node
        node = node.children.first
      end
      nodes.reverse!
    end
    queries = case scenario
    when :first then 1
    when :deep then size
    when :alternating_head, :alternating_tail then 200
    else 1_000
    end
    answers = Array.new(queries)
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    queries.times do |index|
      case scenario
      when :alternating_head, :alternating_tail
        cursor.mark(scenario == :alternating_head ? 0 : size - 1, state: index.even? ? :invalid : :parsed)
      when :mark_only
        cursor.mark(index % size, state: index.even? ? :parsed : :ignored)
      end
      answers[index] = if scenario == :mark_only then true
      elsif scenario == :deep then nodes[index].complete?
      else block.complete?
      end
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat(:total_allocated_objects) - allocations
    expected = queries.times.map do |index|
      scenario == :pending ? false : (%i[alternating_head alternating_tail].include?(scenario) ? index.odd? : true)
    end
    abort "Incorrect completeness" unless answers == expected
    # 仅测量索引容量，不用私有状态替代行为断言；未使用完整性查询时不分配前缀数组。
    prefix = cursor.instance_variable_get(:@unresolved_prefix)
    abort "Unbounded source index" if prefix && prefix.size > size + 1
    puts JSON.generate(scenario: scenario, trial: trial + 1, lines: size, queries: queries, seconds: elapsed,
      allocated_objects: allocations, index_slots: prefix&.size || 0, index_bytes: prefix ? ObjectSpace.memsize_of(prefix) : 0)
  end
end
