# ctx_parser 0.5 契约与迁移

本轮保持现有生产类和模块，收敛声明入口及状态边界。最低运行时为 Ruby 4.0.6。

## 职责与所有权

| 抽象 | 职责及所有权 |
| --- | --- |
| `Commands` | 校验一次声明，拥有冻结的命令、视图和解析器索引；解析器类本身由调用方维护 |
| `Profile` | 持有一份声明和已选型号覆盖，选择解析器并隔离视图投影错误 |
| `Parser` | 文本与传输完整性入口；厂商子类负责解释语法 |
| `Configuration` | 每次解析独立维护文档、来源状态和临时结果路径 |
| `Cursor` / `Document` / `Block` | 来源行、缩进范围及实时语义状态；读过不等于解析成功 |
| `Capture` | 事实和路径是不可变快照，完整性继续查询来源状态 |
| `Result` / `Results` | 不可变事实与诊断；共享回显的每个视图独立保留状态 |
| `Immutable` / `Values` / `Records` | 纯数据快照、严格值转换、逻辑身份分组；Records 借用行对象 |

## 单一声明入口

```ruby
class DeviceProfile < CtxParser::Profile
  DECLARATIONS = CtxParser::Commands.new([
    { dimensions: %i[interfaces counters], command: "show interfaces", parser: InterfacesParser },
    { dimensions: [ :counters ], command: "show counters", parser: CountersParser }
  ], multi_command: true)
end

profile = DeviceProfile.new(model: "fixture")
profile.commands_for(:counters) # 两条独立命令，不能拼接其正文
profile.queries(%i[interfaces counters]) # 命令 => 请求视图，保持顺序
profile.parser_for(:counters, command: "show counters")

expanded = profile.with_declarations(CtxParser::Commands.new(
  profile.declarations.entries + additional_entries, multi_command: true
))
```

`Profile.new(model: nil, declarations: self.class::DECLARATIONS)` 允许显式注入目录。`Commands.new([])` 表示无查询；`queries([])` 返回冻结空映射，选择不存在的维度或从空请求推断命令仍抛出 `ArgumentError`。

删除子类的 `COMMANDS`、`PARSERS` 常量，改用 `DECLARATIONS`。读取旧常量的代码迁移到 `Profile::DECLARATIONS.by_dimension` / `.parsers`，或实例的 `commands` / `parsers`。旧的双目录声明会报告迁移错误；覆盖 `commands` 或 `parsers` 不再改变解析器选择。

`Commands#commands_for` 总是返回冻结数组；`by_dimension` 保持单命令为 String、多命令为 Array 的既有读取形状。`select_command(dimensions, command: nil)` 要求非空、唯一且已声明的维度；只有唯一公共命令才能隐式推断。显式命令必须提供全部请求视图，选择结果返回目录中已经校验并冻结的命令文本。

每次 Profile 操作只读取一次目录，命令与实现来自同一快照。型号键仍去除外围空白并转为小写；所有声明的型号覆盖在注册或实例创建时校验。`with_declarations` 保留已经选定的覆盖和子类状态，不重跑初始化；若新目录删除了选中覆盖需要的命令，则拒绝替换。改变类常量仅影响新实例。

## 来源与快照边界

`analyze`、`analyze_children`、`ignore`、`scope` 在回调前拒绝其他游标的块。参数失败不修改来源状态。`scope` 进入前固定路径，结束时复制产生的事实；嵌套异常仍恢复父路径。

`Immutable.copy` 和 `copy_string` 不保留字符串子类、附加状态或单例行为。输入、命令和来源行采用同一纯文本原则；编码及原始换行策略不变。循环容器仍拒绝。容器即使冻结也重建，单次复制通过身份索引保留共享引用；不同次复制不保证同一容器对象身份。字符串通过 `String.new` 后调用 Ruby 的一元 `-` 去重并冻结。该策略隔离所有可见性的单例行为，也避免枚举每个值的方法表；不新增应用级缓存。

这是对原计划复用冻结容器策略的调整：全量反射检查在本机让重复包装冻结记录慢约 9 倍，且空扩展模块后续新增方法仍可能改变已冻结输入的行为。重建容器消除了这两类问题。记录的值、顺序和一次快照内部的共享引用关系不变。

未更改 Result 字段 `status/records/issues/covered_scopes`、complete/partial/failed/unsupported 状态、共享视图失败隔离、来源完整性的实时查询或 Records 的借用约定。`complete: true` 仍只是调用方的接收完整性声明。

## 消费模块与验证

候选版本为 ctx_parser 0.5.0、ctx_driver/ctx_runner 0.5.1、ctx_checker 0.7.0、vxlan 0.9.0、wireless-rb 0.10.0。Driver/Runner 接受 parser 0.4 与 0.5；迁移后的三个领域模块要求 parser 0.5 及相应 Driver/Runner 补丁版本。报告 schema 不变。

运行 `bundle exec rake`、`bundle exec rake build` 和 `ruby script/verify_package.rb pkg/ctx_parser-0.5.0.gem`。`examples/declarations.rb` 演示新入口；`benchmark/commands.rb`、`profile.rb`、`snapshots.rb`、`source.rb`、`configuration.rb` 分别覆盖声明、选择、事实快照与来源追溯。性能比较必须同时包含构建、首次使用与复用成本，并校验结果相同。

本地测量与正确性成本见 [性能记录](performance-0.5.md)。

## 后续打磨：容器与来源区间

声明、解析请求、子块、捕获来源列表和 Records 行列表在校验及回调前通过 Array.new 固定普通数组。列表由库拥有，解析器类、来源块与 Records 行仍按原契约借用；不继承调用方的 dup/map 行为。

`Cursor#resolved?(first_index, last_index)` 接受零起始闭区间。越界参数抛出 IndexError，逆序区间抛出 ArgumentError；空文档没有可查询的有效闭区间。Block#complete? 委托该查询，Capture 的完整性仍跟随当前来源状态。

Cursor 按需构建未解决行数量的前缀索引，只延伸到已查询末行。mark 在 resolved/unresolved 分组变化时将有效边界退回修改位置，parsed 与 ignored 互换不使索引失效。unread/defer 通过 mark 更新，reset! 释放索引；读取、回退和 rewind 不改变语义状态。稳定查询 O(1)，失效登记 O(1)，重建成本与需要重算的前缀区间长度成正比，空间最多 O(n)。索引属于单次解析游标，不承诺线程共享或缓存旧完整性结论。
