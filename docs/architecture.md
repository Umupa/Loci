# 架构

设计的来龙去脉在 [design.md](design.md)。这一页只说代码怎么分，以及哪些是工具强制的。

## 模块

```
                 Loci（应用）
           ╱           ╲
       LociUI          LociHost
           ╲       ╱   │   │   │   ╲
            ╲  Store Agents Media Code Remote
             ╲    ╲    │    │    │    ╱
                    LociModel
```

| 模块 | 职责 | 可以引用 |
|---|---|---|
| `LociModel` | 值类型、定位符、Host 协议与命令的请求和响应、线路注册表；系统框架可用 CryptoKit（`MachineID` 是公钥的指纹，邀请链接带校验和） | 无 |
| `LociStore` | 文件读写与监听、SQLite、全文索引、伙伴的 `agent/` 文件夹；配对名单与别的 Mac 的缓存；系统框架可用 Security（设备私钥、读其他浏览器 cookie 的密钥）、CryptoKit（缓存文件名）、Darwin（按目录描述符访问取材缓存）、CommonCrypto（解密 Chromium 浏览器的 cookie：AES-CBC 与 PBKDF2，CryptoKit 没有） | `LociModel`；第三方：GRDB |
| `LociAgents` | 各家 agent CLI 的协议驱动、会话、权限 | `LociModel` |
| `LociMedia` | 取回链接（yt-dlp、网页正文、PDF）、组件、Loci 自己的新版本（GitHub release、挂载 dmg、核对签名）、转录、断句、区分说话人；系统框架可用 AVFoundation、CoreMedia、CoreGraphics（PDF 元数据）、PDFKit（PDF 正文）、NaturalLanguage、WebKit（在不显示的网页里取正文）、Synchronization | `LociModel`；第三方：swift-markdown、FluidAudio |
| `LociCode` | 符号大纲、跳转定义、查找引用 | `LociModel` |
| `LociRemote` | 配对、加密通道（Noise）、中继（alma-relay 协议）、局域网发现（Bonjour）、`loci` 命令连进来的本机 unix socket；系统框架可用 CryptoKit、Network | `LociModel` |
| `LociHost` | 命令层的实现：本机和远程；伙伴的会话、上下文拼装与每日回顾；系统框架可用 IOKit（有已配对的 Mac 时阻止空闲睡眠，读机型） | 以上全部 |
| `LociUI` | 界面与设计系统；系统框架可用 AVKit、AVFoundation（播放）、PDFKit（论文）、WebKit（内置浏览器） | `LociModel`；第三方：swift-markdown、Textual、HighlightSwift、SwiftMath |
| `Loci` | 应用入口，把界面接到 Host 上 | `LociModel` `LociUI` `LociHost` |
| `LociTool` | `loci` 命令：读参数，把动词翻成 Host 命令，经本机 socket 发给应用，打印回复。打包成 `Contents/Helpers/loci` | `LociModel` `LociRemote` |

现在已经存在的模块：`LociModel`、`LociStore`、`LociAgents`、`LociMedia`、`LociRemote`、`LociHost`、`LociUI`、`Loci`、`LociTool`。其余在用到时创建，创建时照这张表。

## 三条不变量

1. **界面只认 Host 协议。** `LociUI` 引用不到 `LociStore`、`LociAgents`，它只能发命令、订阅数据。本机和远程因此是同一套界面。
2. **每条出口只有一个主人。** 磁盘归 `LociStore`，外部程序归 `LociAgents` 和 `LociMedia`，网络归 `LociMedia` 和 `LociRemote`。本机的 unix socket 也算网络：Network 框架只在 `LociRemote`，应用这头（`LociHost`）和 `loci` 命令那头（`LociTool`）都经它收发。
3. **核心不依赖界面。** 除了 `LociUI` 和 `Loci`，没有模块引用 SwiftUI 或 AppKit。关掉窗口，会话照样跑。

第三方依赖也记在这张表里，模块只能引用它那一行列出的包；新增一个之前先问。版本都钉死在 `Package.swift` 里：

| 包 | 版本 | 模块 | 用在哪 |
|---|---|---|---|
| GRDB | 7.11.1 | `LociStore` | SQLite 与全文索引 |
| swift-markdown | 0.9.0 | `LociUI` `LociMedia` | 阅读器把文章的 Markdown 解析成 TextKit 2 的文字；文章按段切开去翻译，界面按同样的段找译文 |
| Textual | 0.5.0 | `LociUI` | 对话里伙伴的回复、划线里的回答（流式 Markdown） |
| HighlightSwift（swift-highlight） | 0.1.1 | `LociUI` | 代码块的语法高亮，纯 Swift，不跑 JavaScript |
| SwiftMath | 1.7.3 | `LociUI` | 公式排版 |
| whisper.cpp（`whisper.xcframework`） | b5454（与 v1.9.5 同一次构建，校验和钉在 `Package.swift`） | `LociMedia` | 本机语音识别（Metal），逐词时间 |
| FluidAudio | 0.17.7 | `LociMedia` | 本机区分播客说话人，模型按需下载 |
| defuddle | 0.19.6 | `LociMedia`（资源） | 在不显示的网页里取正文转 Markdown。npm `defuddle@0.19.6` 的 `dist/index.full.js` 原样放在 `Sources/LociMedia/Resources/defuddle.js`，许可证在旁边；升级时换这两个文件并改这里的版本 |

Textual 自带 swiftui-math、swift-concurrency-extras 两个传递依赖。GCD 只允许出现在 `Sources/LociStore/FileEvents.swift`：FSEvents 只能把回调交给一个队列，那个文件接到回调后立刻转成 `AsyncStream`。

这三条都由 `Tests/ArchitectureTests` 检查。那里的 `Architecture.swift` 是这张表的可执行版本，两处一起改。

## 目录

```
Package.swift                 目标和依赖
Sources/<模块>/                一个文件一个类型或一件事
Tests/<模块>Tests/             模块的行为
Tests/ArchitectureTests/      架构规则和它自己的测试
Tests/LociUITests/Snapshot    把界面渲染成图
script/                       check · test · affected · format · bundle · run · release · measure-launch
docs/                         路线、设计、架构、功能地图、agent、发布
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
| 黑盒 | 不读源码，只按场景操作真实应用 | 按 [agents/blackbox.md](agents/blackbox.md) 派出去做 |

真实的 agent CLI、真实的网络只出现在评测和黑盒里，`script/check` 不依赖它们。

以下例外都在 `Tests/LociAgentsTests`：

- `SystemLauncherTests` 会启动 `/bin/cat` 和 `/bin/sh`。把管道接成 `AsyncStream` 的那一层只有对着真实进程才测得出问题（退出与最后一块输出的先后、写给已经退出的进程），这两个程序每台 Mac 都有，不碰网络。别的测试不启动程序。
- `PiLiveTests` 对着真实的 pi 跑，默认跳过，`LOCI_PI=<pi 的路径>` 时才跑，会花一点额度。加上 `LOCI_PI_RECORD=<目录>`，它把每段对话录成 fixture；`PiReplayTests` 在 `script/check` 里回放这些录音。pi 升级后重录一遍，就知道协议变了没有。
- `OmpLiveTests` 同样默认跳过，用 `LOCI_OMP=<omp 的路径>` 开启、`LOCI_OMP_RECORD=<目录>` 录制；`OmpReplayTests` 离线回放 omp 的真实录音。

另外，`LocalSocketTests`（`Tests/LociRemoteTests`）和 `ToolScenarioTests`（`Tests/LociHostTests`）在 `/tmp` 下开真实的 unix socket：socket 路径最长 104 字节，系统的临时文件夹太深。不碰网络。
