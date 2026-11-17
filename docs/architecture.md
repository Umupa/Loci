# 架构

设计的来龙去脉在 [design.md](design.md)。这一页只说代码怎么分，以及哪些是工具强制的。

## 模块

```
            Loci（应用）          LociEval（评测）
           ╱           ╲              │
       LociUI          LociHost ──────┘
           ╲       ╱   │   │   │   ╲
            ╲  Store Agents Media Code Remote
             ╲    ╲    │    │    │    ╱
                    LociModel
```

| 模块 | 职责 | 可以引用 |
|---|---|---|
| `LociModel` | 值类型、定位符、Host 协议与命令的请求和响应 | 无 |
| `LociStore` | 文件读写与监听、SQLite、全文索引 | `LociModel`；第三方：Yams、GRDB |
| `LociAgents` | 各家 agent CLI 的协议驱动、会话、权限 | `LociModel` |
| `LociMedia` | 取回、转录、断句、翻译、章节与重点 | `LociModel` |
| `LociCode` | 符号大纲、跳转定义、查找引用 | `LociModel` |
| `LociRemote` | 配对、加密通道、中继 | `LociModel` |
| `LociHost` | 命令层的实现：本机和远程 | 以上全部 |
| `LociUI` | 界面与设计系统 | `LociModel` |
| `Loci` | 应用入口，把界面接到 Host 上 | `LociModel` `LociUI` `LociHost` |
| `LociEval` | 评测，不随应用发布 | `LociModel` `LociHost` |

现在已经存在的模块：`LociModel`、`LociStore`、`LociUI`、`Loci`。其余在用到时创建，创建时照这张表。

## 三条不变量

1. **界面只认 Host 协议。** `LociUI` 引用不到 `LociStore`、`LociAgents`，它只能发命令、订阅数据。本机和远程因此是同一套界面。
2. **每条出口只有一个主人。** 磁盘归 `LociStore`，外部程序归 `LociAgents` 和 `LociMedia`，网络归 `LociMedia` 和 `LociRemote`。
3. **核心不依赖界面。** 除了 `LociUI` 和 `Loci`，没有模块引用 SwiftUI 或 AppKit。关掉窗口，会话照样跑。

第三方依赖也记在这张表里，模块只能引用它那一行列出的包；新增一个之前先问。GCD 只允许出现在 `Sources/LociStore/FileEvents.swift`：FSEvents 只能把回调交给一个队列，那个文件接到回调后立刻转成 `AsyncStream`。

这三条都由 `Tests/ArchitectureTests` 检查。那里的 `Architecture.swift` 是这张表的可执行版本，两处一起改。

## 目录

```
Package.swift                 目标和依赖
Sources/<模块>/                一个文件一个类型或一件事
Tests/<模块>Tests/             模块的行为
Tests/ArchitectureTests/      架构规则和它自己的测试
Tests/LociUITests/Snapshot    把界面渲染成图
script/                       check · format · run
docs/                         路线、设计、架构、功能地图
docs/agents/                  派活、审阅、黑盒测试的说明
docs/spikes/                  验证的结论
output/                       构建产物、截图、日志（不提交）
```

## 工程选择

- **只用 SwiftPM，没有 Xcode 工程。** 工程文件在多个 worktree 并行时总是冲突，也没法审阅。应用包由 `script/run` 组装。
- **Swift 6 语言模式，警告即错误。** 并发问题在编译期解决。
- **测试用 Swift Testing。**
- **格式用工具链自带的 `swift format`**，配置在 `.swift-format`。
- **架构规则写成测试**，不依赖额外的 lint 工具，报错信息直接给出改法。

## 测试分层

| 层 | 测什么 | 在哪 |
|---|---|---|
| 行为 | 一个模块对外承诺的事，不碰真实磁盘、网络、外部程序 | `Tests/<模块>Tests` |
| 架构 | 边界与禁用写法 | `Tests/ArchitectureTests` |
| 界面 | 渲染成图，亮暗两套 | `Tests/LociUITests` |
| 场景 | `features.md` 里的场景，经 Host 走完整条路 | `Tests/LociHostTests`（模块出现后） |
| 评测 | 导师写课的质量，用 Pi 跑 | `LociEval`（模块出现后） |
| 黑盒 | 不读源码，只按场景操作真实应用 | 按 [agents/blackbox.md](agents/blackbox.md) 派出去做 |

真实的 agent CLI、真实的网络只出现在评测和黑盒里，`script/check` 不依赖它们。
