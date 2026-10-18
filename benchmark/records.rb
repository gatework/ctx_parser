# frozen_string_literal: true

require 'ctx_parser/records'
size = 100_000
{ unique: size, pairs: size / 2, one: 1 }.each do |name, identities|
  rows = Array.new(size) { |index| { id: index % identities } }
  samples = 5.times.map do
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = CtxParser::Records.new(rows, identity: [ :id ])
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    raise 'identity mismatch' unless result.first_occurrences.size == identities && result.duplicate_row_count == size - identities
    [ elapsed * 1000, GC.stat(:total_allocated_objects) - allocated ]
  end
  p [ name, samples.sort_by(&:first)[2] ]
end
