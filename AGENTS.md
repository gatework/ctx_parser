# ctx_parser 开发指南

本文件适用于本仓库。用户指令优先；更深目录的 AGENTS.md 可细化局部约定。

## 职责与结构

这是独立于 Rails 的 CLI 文本解析基础库。只提供来源模型、解析接口、命令目录和值对象；厂商语法及健康策略由消费模块负责。加载库不得建立连接或加载宿主应用。

- `lib/ctx_parser/input.rb`：编码、换行、NUL 及输入字节预算。字节限制在转码前检查，不按字符数计算。
- `cursor.rb`、`line.rb`、`block.rb`、`document.rb`：原始来源、缩进树、行状态及可追溯范围。
- `configuration.rb`：语义分析、作用域和来源捕获；每次解析重置状态。
- `parser.rb`、`result.rb`、`results.rb`：统一解析接口及不可变的单视图/多视图结果。
- `commands.rb`、`profile.rb`、`registry.rb`：声明校验、型号覆盖、命令选择及共享视图投影。
- `immutable.rb`、`records.rb`、`values.rb`：纯数据快照、身份冲突及严格值转换。

## 必须保持的契约

- `Parser.parse(text, complete: false)` 每次使用新实例；`complete: true` 仅表示调用方声明接收完整，不能覆盖解析诊断。
- `Result` 状态为 complete/partial/failed/unsupported。共享命令只解析一次，`Results` 的每个视图独立投影，缺失或异常视图不能抹掉其他事实。
- 游标访问状态与语义状态分开；读过不代表 parsed。未知行保留，只有明确领域外内容才能 ignored。
- 配置块必须属于同一游标、按来源排序且无重叠；深层树使用显式栈，避免 Ruby 递归栈溢出。
- 捕获值和路径是快照，来源状态可继续推进；不要缓存会过时的完整性结论。
- `Immutable.copy` 拒绝循环和非纯数据。只复用已验证的深冻结容器，不能继承 Hash 默认回调等特殊行为。
- Profile 的命令缓存仅复用已验证的冻结目录；动态替换和可变目录继续校验。并发读取得到完整快照，不混用目录与成员索引。
- 默认 inspect/to_s/pretty_print 和元数据序列化不泄露来源正文；显式来源访问接口保留原有契约。

## 开发约定

- 使用 `.ruby-version`、gemspec 和锁文件规定的运行时与依赖；当前 Ruby 最低版本和 CI 版本为 4.0.6。修改版本策略时同步检查这三处及 CI。
- 遵循 `.rubocop.yml`：两空格缩进、snake_case 方法和文件、UpperCamelCase 类型、`frozen_string_literal`。代码注释沿用中文，RSpec 示例及 Changelog 沿用英文。
- 厂商 CLI 命令解析器的文件名、类名及目录应继续镜像原命令；必要修复不受限制。命名清理优先针对语义不清的适配器和辅助对象。
- 先查调用者和既有同类实现。抽象应保护业务不变量或隔离协议，不因文件长度或方法数量机械拆分。
- 区分缺失、nil、false、非法和未知。异常只在负责的边界处理；不能用空集合、零值或成功状态掩盖失败。
- 不依赖 Ruby 全局分隔符 `$;`、`$/`、`$,`；拆分、逐行读取和拼接须指定分隔符。处理配置时保留来源原文及换行。
- 在外部回调前固定已校验输入和证据。不要冻结调用方的可变对象；`Data.define` 和外层 `freeze` 不等于成员深度不可变。
- 保留暂存、未暂存和未跟踪改动；不覆盖无关工作，不执行 reset/clean/stash。审查与本地修复本身不代表获得提交、推送或发布授权。

## 验证与交付

在本仓库根目录执行：

```sh
ruby -v
bundle exec rake
bundle exec rake build
```

`rake` 默认包含 RSpec、RuboCop 和全部 examples；examples 使用本地合成数据，不需连接设备。若非交互 shell 误用 macOS 系统 Ruby 2.6，在当前环境使用 `zsh -ic 'bundle exec rake'`；不要为此降级锁文件或修改依赖。

- 缺陷先用最小回归复现，再修复；优先复用已有测试。测试断言实际输出、错误隔离和副作用，不镜像内部实现。
- 性能改动使用 `benchmark/` 中的脚本，记录输入规模、Ruby 版本、代码来源、耗时和分配量；比较前后语义。合成结果不能证明网络吞吐或实机兼容性。
- 公共行为变化记录在 `CHANGELOG.md` 的 Unreleased。当前代码、README 和验证脚本是依据；`docs/architecture-zh.md` 含历史 Motor 宿主记录，不能当成当前 gem 的运行能力。
- 跨仓库联调与锁定依赖测试分别运行并报告。`RUBYLIB` 联调通过不证明已发布依赖兼容；使用 `script/verify_package.rb` 在隔离安装中验证候选包。
- 只有明确要求发布时才执行交付流程，顺序为 ctx_parser → ctx_driver → ctx_checker；核对精确提交的 CI、制品、校验和及安装读回结果。仓库可见性仅按当前授权调整。

独立安装验证：`ruby script/verify_package.rb pkg/ctx_parser-*.gem`。重点回归包括混合换行、编码、分隔符污染、深层配置、重复身份、可变输入和共享视图失败隔离。基准入口示例：`bundle exec ruby -Ilib benchmark/input.rb`、`benchmark/source.rb`、`benchmark/profile.rb`。
