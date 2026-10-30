# frozen_string_literal: true

require "ctx_parser"

# 合成解析器只演示声明与投影，不连接设备。
class DeclarationStatusParser < CtxParser::Parser
  private

  def parse_output(text, complete:)
    CtxParser::Result.new(status: complete ? :complete : :partial, records: [ { value: text.strip } ])
  end
end

catalog = CtxParser::Commands.new([
  { dimensions: %i[inventory counters], command: "show inventory", parser: DeclarationStatusParser }
])
profile = CtxParser::Profile.new(declarations: catalog)
views = profile.parse_many(%i[inventory counters], "synthetic\n", complete: true)
abort "Shared view selection changed" unless views.keys == %i[inventory counters] && views.values.all?(&:complete?)

expanded = profile.with_declarations(CtxParser::Commands.new(catalog.entries + [
  { dimensions: [ :alarms ], command: "show alarms", parser: DeclarationStatusParser }
]))
abort "Original catalog changed" if profile.commands.key?(:alarms)
abort "Expanded query missing" unless expanded.command(:alarms) == "show alarms"
puts "Commands: shared views and independent profile expansion passed"
