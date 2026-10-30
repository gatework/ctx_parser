# frozen_string_literal: true

require "rubygems/package"
require "tmpdir"
require "rbconfig"
require "fileutils"

# 仅验证发布文件与解析后的依赖，避免从工作区加载代码。
artifact = File.expand_path(ARGV.fetch(0))
spec = Gem::Package.new(artifact).spec
abort "Unexpected package" unless spec.name == "ctx_parser"
abort "Unexpected package contents" if spec.files.any? { |path| path.start_with?("spec/", "test/", "storage/", "tmp/") || path.end_with?(".log", ".gem") }
Dir.mktmpdir("gem-install-") do |home|
  env = ENV.to_h.keys.grep(/\A(?:BUNDLE_|BUNDLER_|RUBY)/).to_h { |key| [ key, nil ] }
  env.merge!("GEM_HOME" => home, "GEM_PATH" => home, "RUBYOPT" => nil, "RUBYLIB" => nil)
  ruby = RbConfig.ruby
  # 重定位工具链只补入标准库目录；不能让工作区 RUBYLIB 混入隔离安装。
  standard_library = RbConfig::CONFIG.values_at("rubylibdir", "archdir").uniq
  env["RUBYLIB"] = standard_library.join(File::PATH_SEPARATOR)
  ruby_options = standard_library.flat_map { |path| [ "-I", path ] }
  options = []
  if (cache = ENV["CTX_PARSER_GEM_CACHE"])
    files = Dir[File.join(File.expand_path(cache), "*.gem")]
    abort "Dependency cache is empty" if files.empty?
    files.each { |path| FileUtils.cp(path, home) }
    options << "--local"
  end
  system(env, ruby, *ruby_options, "-S", "gem", "install", artifact, "--no-document", *options, chdir: home, exception: true)
  check = <<~RUBY
    require "ctx_parser"
    abort "Unexpected Rails dependency" if defined?(Rails)
    loaded = Gem.loaded_specs.fetch("ctx_parser")
    abort "Loaded checkout instead of package" unless File.realpath(loaded.full_gem_path).start_with?(File.realpath(ENV.fetch("GEM_HOME")) + "/")
    abort "Version mismatch" unless loaded.version.to_s == #{spec.version.to_s.inspect}
    native = Class.new(CtxParser::Document) do
      protected
      def build_blocks
        child = cursor.block(1)
        [CtxParser::Block.new(cursor: cursor, header: cursor.lines.first, children: [child], last_index: 2)]
      end
    end
    document = native.new("parent\\nchild\\nend\\n")
    abort "Native document protocol unavailable" unless document.roots.first.children.first.line_range == (2..2)
    flat = CtxParser::Document::Flat.new("first\\n  second\\n")
    abort "Flat document protocol unavailable" unless flat.roots.map(&:line_range) == [1..1, 2..2]
    abort "Unstable line block" unless flat.cursor.block(1).equal?(flat.cursor.block(1))
    Dir[File.join(loaded.full_gem_path, "examples/**/*.rb")].sort.each { |path| load path }
  RUBY
  system(env, ruby, *ruby_options, "-e", check, chdir: home, exception: true)
  puts "Verified isolated install: #{spec.full_name}"
end
