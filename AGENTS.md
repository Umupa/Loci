# 在这个仓库里工作

Loci 是一个 Mac 应用：从你读的、看的、听的东西里学习，身边有一个住在你资料库里的 AI 伙伴。原生 Swift 写成（macOS 26+）。

| 文档 | 写什么 |
|---|---|
| [docs/roadmap.md](docs/roadmap.md) | 做完了哪些版本，下一版做什么 |
| [docs/features.md](docs/features.md) | 功能叫什么、怎样算做对（场景） |
| [docs/design.md](docs/design.md) | 现在的产品、视觉、数据和远程设计 |
| [docs/agent.md](docs/agent.md) | Loci 这个 agent 为什么这样设计 |
| [docs/architecture.md](docs/architecture.md) | 模块怎么分 |
| [CHANGELOG.md](CHANGELOG.md) | 用户看得到的变化，按版本 |

## 一条命令

```sh
script/check
```

格式、编译（警告即错误）、测试、架构与文档检查、还没推送的提交信息都在里面，CI 跑的就是它。通过时只打印四行 `ok`；失败时打印哪里错了、该怎么改。交付之前必须通过。

| 命令 | 作用 |
|---|---|
| `script/check` | 唯一的闸门 |
| `script/format` | 按项目风格重排代码 |
| `script/run` | 构建并打开 `output/Loci (Beta).app`；`--no-open` 只构建 |
| `script/cut-release <版本>` | 定一个版本：改 CHANGELOG、跑闸门、提交、打 tag |

## 这个仓库是你的教材

你会模仿仓库里已有的代码，下一个人会模仿你写的。所以仓库里只留值得被模仿的东西：

- 不合并临时补丁、绕过、占位实现、「以后再说」。做不完就缩小范围，把没做的写在交付说明里。
- 验证用的一次性代码放在 `spike/*` 分支，不合并；合并的只有结论（`docs/spikes/<名字>.md`）。
- 旧的 Tauri 版留在 `tauri` 标签上。它只说明**行为**（一个功能应该做什么、协议长什么样），可以用 `git show tauri:<路径>` 查；它的结构、命名、写法不要搬过来。

## 工具替你守住的

下面这些不用记，违反时 `script/check` 会指出位置和改法。规则本身在 `Tests/ArchitectureTests/Architecture.swift`。

- 模块只能引用架构表允许的模块和系统框架。界面碰不到存储，只有 `LociStore` 碰磁盘，只有 `LociAgents` 和 `LociMedia` 启动外部程序，只有 `LociMedia` 和 `LociRemote` 用网络。
- 不写注释。`///` 只用来说明一个声明承诺什么。
- 不用 `try!`、`as!`、`fatalError`、`print`，不绕过并发检查，不用 GCD 和锁。
- 不留 `TODO`。源文件不超过 400 行。每个库模块都有测试。
- 文档不说旧词：`docs/features.md` 末尾「不再用的词」里的词，出现在文档、未发布的 CHANGELOG 或 `Sources` 里就报错。
- 文档里的链接和 `Sources/…`、`Tests/…` 这类路径必须存在；功能地图里每个词对应的类型必须在代码里声明。

规则挡住了你，先假设规则是对的，去改设计。确实是规则错了，就在同一次改动里改规则，并在交付说明里写明原因。不要想办法绕过去。

## 版本怎么走

1. **规划**：在 `docs/roadmap.md` 的「接下来」写下一版的主题和范围，场景写进 `docs/features.md`，带编号。
2. **开发**：`feat` 和 `fix` 的提交在 `CHANGELOG.md` 的 Unreleased 下写最终状态（`script/check` 会检查）。还没发布的功能又改了，就改原来那条，不追加；删了，就删那条。
3. **发版**：roadmap 里把这一版挪进「已完成」，然后 `script/cut-release <版本>`，推送 tag。整个流程见 [docs/releasing.md](docs/releasing.md)。

## 文档只写现在

- 删掉或改名一个东西，在同一次改动里：删代码、删或改文档里写它的地方、把旧词加进 `docs/features.md` 的「不再用的词」。`script/check` 会列出所有漏掉的地方。
- `design.md`、`agent.md`、`features.md` 写现在的样子，不写「当时的记录」「已作废」。计划放在 roadmap，做完的进 CHANGELOG，过程留给 git 历史。
- 同一件事只写在一个地方，别处链接过去。规则和格式写在代码旁边的，文档里只指过去，不重抄。

## 需要你自己判断的

- **先写测试说明的行为，再写实现。** 测试名是一句话，说的是用户或调用方看得到的行为，不是实现细节。
- **让错误的状态表示不出来。** 能用类型挡住的，不靠运行时检查，更不靠文档提醒。
- **不为假想的需求加抽象。** 第二个用处出现时再抽。
- **时间、随机数、文件位置、外部程序都从外面传进来**，测试里可以换掉。参照 `EntityID.init(at:entropy:)`。
- **名字用 [docs/features.md](docs/features.md) 里的词。** 那是人和 agent 共用的词汇，代码里的类型名与它一一对应。
- **界面文字**不要副标题和解释性的小字，让布局说明自己。中英两种语言都要有。
- 代码、标识符、提交信息用英文；文档用中文。

## 每次被纠正，留下一条检查

你被人或被另一个 agent 纠正时，先问一句：这个错能不能让工具下次自己拦住？按这个顺序找落点：

1. 改类型或 API，让它写不出来。
2. 加一条架构规则（`Architecture.swift`），报错信息写清楚该怎么改。
3. 加一个测试。
4. 以上都不行、确实需要判断的，才写进这份文件。

同一个错不该被人指出第二次。

## 自己验证，拿证据交付

说「做完了」之前：

- `script/check` 通过，把输出贴出来。
- 改了界面：用 `Tests/LociUITests/Snapshot.swift` 给亮色和暗色各渲染一张，看过图再交。图在 `output/snapshots/`。
- 对照 `docs/features.md` 里这次涉及的场景，逐条说明怎么验证的。没验证的明说没验证。
- 用户看得到的变化，在 `CHANGELOG.md` 的 Unreleased 下加一行。

## 提交

- 提交信息用 Conventional Commits，祈使句：`feat: open a pasted link in the library`。`feat`、`fix` 必须同时改 CHANGELOG；用户看不到的改动用别的类型。
- 一次改动一个主题。不提交生成的文件（`.build/`、`output/`）。
- 新增第三方依赖要先问。每个依赖都要在交付说明里写明为什么不自己写。
