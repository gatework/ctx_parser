# ctx_parser

[English](README.md) | [源码](https://github.com/gatework/ctx_parser) | [变更记录](CHANGELOG.md)

面向网络 CLI 解析的纯 Ruby 公共组件，提供不可变结果、来源游标、配置树、命令目录及平台策略。厂商语法和设备会话由对应领域模块负责。

## 能力

- `Parser`、`Configuration` 定义文本输入及完整性边界。
- `Cursor`、`Document`、`Capture` 保留来源位置和嵌套配置上下文。
- `Profile`、`Commands`、`Registry` 声明平台/型号行为，同一回显可共享解析。
- `Values`、`Records`、`Immutable` 统一值转换、身份检查与防御性复制。

## 安装

要求 **Ruby 4.0.6 或更新版本**。在应用的 `Gemfile` 中添加：

```ruby
gem "ctx_parser"
```

然后执行 `bundle install`；也可直接执行 `gem install ctx_parser`。Ruby 加载入口为 `ctx_parser`，公开命名空间为 `CtxParser`；gem 包名与 Ruby 命名空间分别维护。

本模块不依赖其他 Gatework 领域 gem。 gemspec 声明 `ipaddr` 和 `digest`，不限制版本；运行依赖组合应由应用锁文件固定并验证；应用应提交自己的 `Gemfile.lock`，保持部署可复现。使用本库不需要启动 Rails 或配置兄弟模块的本地路径。

发布产物和校验值见 [GitHub Releases](https://github.com/gatework/ctx_parser/releases)，已发布版本以 [RubyGems](https://rubygems.org/gems/ctx_parser) 为准。

## 离线示例

在开发检出目录安装依赖后执行：

```sh
bundle exec ruby examples/offline.rb
```

示例使用合成数据，不访问网络。完整代码见 [examples/offline.rb](examples/offline.rb)：

```ruby
require "ctx_parser"

# 示例仅实现小型语法；厂商语法应放入对应领域 gem。
class ExampleStatusParser < CtxParser::Parser
  private

  # 保留未知行，并遵循调用方声明的传输完整性。
  def parse_output(text, complete:)
    records = []
    issues = []
    text.each_line("\n").with_index(1) do |line, number|
      next if line.strip.empty?

      match = /\A([A-Za-z0-9\/]+) (up|down)\z/.match(line.strip)
      if match
        records << { name: match[1], state: match[2].to_sym }
      else
        issues << { code: :unrecognized_row, line: number }
      end
    end
    status = complete && issues.empty? && !records.empty? ? :complete : :partial
    CtxParser::Result.new(status: status, records: records, issues: issues)
  end
end

result = ExampleStatusParser.parse("Eth1/1 up\nEth1/2 down\n", complete: true)
puts "Parse status: #{result.status}"
result.records.each { |row| puts "#{row[:name]}: #{row[:state]}" }
```

## 公开契约与限制

`Parser.parse(text, complete: false)` 返回包含 `status`、`records`、`issues` 的 `Result`；多视图解析器可返回 `Results`。状态为 `complete`、`partial`、`failed`、`unsupported`。子类实现 `parse_output`，配置子类通过 `analyze` 和 `capture` 保留来源。

`complete: true` 只表示调用方确认输入完整接收，不证明所有语法都已理解。未知行、身份冲突及空表证据不足必须明确表达。结果的记录和诊断均须为 Hash 数组；结果及构建完成的文档诊断持有不可变快照。`inspect`、`to_s` 和 pretty printing 不输出结果正文与诊断内容，显式读取记录仍返回原始事实。来源游标有意保留输入原文，含秘密时不可写入日志。

`Cursor#resolved?(first_index, last_index)` 查询零起始闭区间；Block/Capture 完整性继续读取实时来源状态。惰性前缀索引在解决状态变化后失效，reset 时清空，详见 [0.5 契约](docs/contracts-0.5.md)。

本 gem 不提供厂商命令目录、传输、持久化或健康策略。参数和注册表配置错误保持异常，由调用方在对应边界处理。

详细厂商语义、历史验证记录和 Motor 专用集成说明保留在[架构参考](docs/architecture-zh.md)。其中宿主集成代码需要 Motor，不属于独立 gem API。适配层位于 [Motor 仓库](https://github.com/gatework/motor/tree/main/backend/lib) 的 `backend/lib/baseline`、`backend/lib/vxlan` 和 `backend/lib/wireless`。

## 领域术语

名称使用领域名词：`Configuration` 解析配置文档，`Result` 表示单个结果，`Results` 保存具名结果，`Commands` 保存命令声明。两个集合均用 `by_dimension` 表示维度索引。通用 `Parser` 负责文本解析契约，配置来源状态归 `Configuration` 管理。

维度是具名事实视图，命令是提供这些事实的 CLI 查询。`Profile#queries` 按命令归组维度，型号覆盖按命令选择解析器。`Records` 按逻辑身份归组记录；重复身份数与多余记录数是不同数量。`Line`、`Block`、`Capture` 保留来源位置，`Result` 承载归一化事实与诊断。解析完整性或空结果都不能证明设备健康。

地址转换使用 `Values.ip_address`、`Values.ip_address?`、`Values.mac_address`。`Values.ipv4_prefix(..., preserve_host_bits: true)` 明确保留接口主机位，默认返回网段前缀。

`Cursor.new(text, max_bytes: limit)` 和 `Document.new(source, max_bytes: limit)` 可在构建或消费来源行前限制输入字节数。传入已有游标时，限制针对其归一化内容。非法编码仍抛出错误；已知为 Latin-1 的输入可先标记 `Encoding::ISO_8859_1`，随后自动转为 UTF-8，不静默替换字节并生成事实。

`MODEL_PARSERS` 的型号键与请求型号一样去除两侧空白并转为小写，归一化冲突和无效覆盖均被拒绝。`Registry` 在注册时校验 Commands 声明及型号覆盖；Profile 创建时快照选中的覆盖，派生实例继续持有原先的型号设置。

`Commands` 独立持有不可变查询序列及命令到视图的索引。静态声明使用 `DECLARATIONS = CtxParser::Commands.new(...)`，也可向 `Profile.new` 传入 `declarations:`。发现阶段通过 `profile.with_declarations(new_catalog)` 返回副本，原实例保留原目录。`commands`、`parsers` 只是派生查询接口，旧的 `COMMANDS/PARSERS` 双目录声明会被拒绝。空目录合法，查询不存在的维度仍抛出 `ArgumentError`。详见 [0.5 契约与迁移](docs/contracts-0.5.md)。`benchmark/profile.rb` 覆盖 32–4096 条命令，`benchmark/commands.rb` 同时测量声明构造成本。

`Records` 持有自己的筛选数组，行对象仍属于调用方；使用期间应保持行不变，需要快照时传入 `Immutable.copy(rows)`。`Immutable.copy` 即使遇到冻结容器也重建普通容器，单次复制中保留共享引用并拒绝循环；不扫描方法表，也不引入应用级全局缓存。字符串经 `String.new` 和 Ruby 去重后冻结，保留编码与字节。不同次复制不保证容器对象身份相同；`Immutable.copy_string` 提供相同的文本边界并省去容器遍历表。整数转换仅在 `min` 允许负数或为 `nil` 时接受负号，默认仍只接受非负数。

`Document` 默认按缩进建树；原生语法可以覆盖受保护的 `build_blocks`，返回同一游标内按来源排序、互不重叠的根 Block，随后仍执行 `finish`。子块必须处于父范围内并保持顺序，不要求更深缩进。`Document::Flat` 将命令行作为独立来源块；`cursor.block(index)` 复用单行范围，rewind/reset 保留其身份，完整性始终读取当前游标状态。这些 API 由配套 0.5.1 候选提供，厂商语法由消费模块拥有。

## 开发与测试

共享类按实际职责命名，平台信息放在命名空间中。直接对应设备命令的解析器保留文件名和类名。

```sh
bundle install
bundle exec rake
bundle exec ruby examples/offline.rb
bundle exec rake build
```

`bundle exec rake` 执行 RSpec、RuboCop 及离线示例。测试放在 `spec/`，沿用项目 RSpec 约定；样例采用合成或脱敏证据。新增解析格式时补充成功、不完整、不支持及非法输入回归。离线测试不代表所有设备版本均通过实机验证。

使用声明的最低 Ruby 版本检查兼容性。方法用途统一使用简明中文注释；复杂实现还需说明业务规则、实现思路及关键分支。保持公开返回值与错误契约。真实回显和凭据不可进入示例、fixture、日志或发布包。

这些开发命令须在源码检出目录执行；测试、基准和脚本有意排除在安装包之外。

执行 `bundle exec ruby -Ilib benchmark/snapshots.rb` 可测量冻结结果的重复封装；执行 `bundle exec ruby -Ilib benchmark/source.rb`，可使用合成输入和语义断言测量游标及文档构建的耗时与对象分配量，无需领域 gem。此类本地测量不代表设备性能。

## 发布

本目录可独立维护为 [ctx_parser](https://github.com/gatework/ctx_parser) 仓库。更新 `VERSION` 和 `CHANGELOG.md`，运行上述验证与构建命令，检查包内文件，再创建 `vVERSION` 标签。

CI 在 Linux、macOS 上执行测试、lint、示例、构建和隔离安装。`main` 的 CI 通过后推送 `vVERSION` 标签，工作流将已验证的 Linux 产物发布到 RubyGems 和 GitHub Release，附带 `SHA256SUMS` 并回读下载字节。GitHub `release` environment 可配置 `RUBYGEMS_API_KEY` secret；未配置时使用 RubyGems Trusted Publishing，绑定本仓库、`release.yml` 和 `release` environment。失败时重跑失败的发布 job，以复用原 CI 产物；同版本已存在时必须校验字节一致。详见[发布说明](docs/release.md)。

先发布依赖模块。标签、构建成功或工作流文件都不等于已经发布，需单独确认 RubyGems 的实际结果。版本变化见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

MIT，见 [LICENSE](LICENSE)。


`Result#partial?` identifies partial parsing; `#available?` is true for complete or partial results. Failed and unsupported results cannot contain records. Availability does not establish completeness or network health.
