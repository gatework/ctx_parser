# frozen_string_literal: true

require "ctx_parser/input"
require "json"

# 合成正文只测输入归一化；语义校验不计入耗时和分配，不代表设备吞吐。
puts RUBY_DESCRIPTION
puts "source=#{CtxParser::Input.method(:text).source_location.first}"
{ lf: "description 无线\n" * 50_000, crlf: "description 无线\r\n" * 50_000,
  latin: ("description café\n" * 50_000).encode("ISO-8859-1") }.each do |name, body|
  expected = body.encode("UTF-8").gsub(/\r\n?/, "\n")
  3.times do |trial|
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = nil
    30.times { result = CtxParser::Input.text(body, encoding: :transcode, newlines: :lf) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocated = GC.stat(:total_allocated_objects) - allocated
    abort "Changed text or ownership" unless result == expected && !result.equal?(body) && !result.frozen?

    puts JSON.generate(case: name, trial: trial + 1, iterations: 30, bytes: body.bytesize,
      seconds: elapsed.round(6), allocations: allocated)
  end
end
