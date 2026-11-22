# 自带 Pi 的验证

2026-11-21。Pi v1.6.0 可以作为独立组件运行。官方 arm64 包在系统 PATH 下通过现有 `PiDriver` 跑完了真实对话，模型也通过应用的 `loci` 命令查到了资料。macOS 发布还需解决签名与公证，官方 x64 包的签名已在本机验证失败。 [Pi v1.6.0 发布页](https://github.com/earendil-works/pi/releases/tag/v1.6.0)

## 发布物、体积和启动

两份 macOS tarball 都有 `SHA256SUMS`，下载后校验通过。压缩包根目录是 `pi/`，内含 Bun 编译的 Mach-O，以及相邻的 `package.json`、WASM、主题、文档和架构对应的原生辅助模块。只复制可执行文件时，`--version` 在本机变成了 `0.0.0`。安装时保留整份目录。两个官方二进制都只动态链接 macOS 系统库，Mach-O 声明的最低系统是 macOS 13。 [Bun 构建脚本](https://github.com/earendil-works/pi/blob/v1.6.0/scripts/build-binaries.sh)

| 官方资产 | 压缩包 | 可执行文件 | 解包文件合计 | RPC 启动中位数 |
|---|---:|---:|---:|---:|
| `pi-darwin-arm64.tar.gz` | 45.90 MiB | 98.68 MiB | 105.93 MiB | 0.94 秒 |
| `pi-darwin-x64.tar.gz` | 48.29 MiB | 107.17 MiB | 114.39 MiB | 2.35 秒（Rosetta） |

在 Apple Silicon、macOS 27.2 上，从派生进程到收到成功的 `get_state`。每次用新配置目录，PATH 只有系统目录，设置 `PI_OFFLINE=1`，每个架构先启动一次，再量 12 次。一次较早的 x64 启动超过 8 秒，放宽时限后完成验证。这组数字只含 RPC 就绪时间，Intel 真机和模型首字延迟待测。

用官方源码包、Node 24.19.0、Bun 1.4.3 和 `scripts/build-binaries.sh --offline-model-data` 重建了两个架构的 tarball。脚本先构建工作区，再用 `bun build --compile` 编入入口和 worker，最后布置配套文件。重建 arm64 在无 Node 的 PATH 下回复了 `get_state`。构建工具留在 CI，用户运行时只需要下载组件。上游发布流水线使用 Bun 1.4.4。 [发布流水线](https://github.com/earendil-works/pi/blob/v1.6.0/.github/workflows/build-binaries.yml)

官方 arm64 文件是 ad hoc 签名，`codesign --verify --strict` 通过，`spctl` 评估拒绝。官方和重建的 x64 文件都报告签名无效，官方包仍在本机 Rosetta 下完成了 RPC 握手。给 x64 的实验副本重新做 ad hoc 签名后，严格校验通过，仍能报告 `1.6.0`。正式组件需通过 Developer ID 签名、公证以及干净 Mac 上的下载启动验证。 [Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Pi 的 MIT 许可证允许再分发，须随副本保留版权和许可声明。官方 tarball 中未发现单独的许可证文件。Loci 如自行构建、重签或镜像分发，打包时补齐 Pi、Bun 和随包依赖的声明，并按所用 Bun 版本确认静态链接的 JavaScriptCore/WebKit 的 LGPL-2 源码与重链接交付义务。上线前核对随包依赖清单。 [Pi 许可证](https://github.com/earendil-works/pi/blob/v1.6.0/LICENSE) · [Bun 许可证与链接依赖](https://github.com/oven-sh/bun/blob/main/LICENSE.md)

## 模型服务和密钥

| 服务 | Pi 的配置 |
|---|---|
| OpenAI | 内置 `openai`，进程环境传 `OPENAI_API_KEY` |
| Anthropic | 内置 `anthropic`，进程环境传 `ANTHROPIC_API_KEY` |
| OpenRouter | 内置 `openrouter`，进程环境传 `OPENROUTER_API_KEY`。免费模型也需要 OpenRouter key |
| DeepSeek | 内置 `deepseek`，进程环境传 `DEEPSEEK_API_KEY` |
| 兼容 OpenAI 的地址 | 在应用专用的 `models.json` 写 `baseUrl`、`api: "openai-completions"` 和模型 ID。用 `"apiKey": "${LOCI_MODEL_API_KEY}"` 引用进程环境变量 |

用 `PI_CODING_AGENT_DIR` 指向 Application Support 下的独立目录，并将 Pi 的会话存入该目录。内置服务只需要环境变量和明确的 `provider/model`，兼容服务由 Loci 生成配置文件。密钥持久化用钥匙串，Pi 启动时读取并注入，配置只写变量名。本次运行生成的 `auth.json` 为空。 [Pi 服务商](https://github.com/earendil-works/pi/blob/v1.6.0/packages/coding-agent/docs/providers.md) · [模型配置](https://github.com/earendil-works/pi/blob/v1.6.0/packages/coding-agent/docs/models.md) · [环境变量](https://github.com/earendil-works/pi/blob/v1.6.0/packages/coding-agent/docs/environment-variables.md)

Pi 的 Bash 工具默认继承进程环境。通过专用 `settings.json` 的 `shellPath` 指向 Loci 提供的启动脚本，清除模型凭据变量后再执行系统 Bash。实测 Bash 看不到注入的 key，`loci` 仍可用。该做法限制普通命令的环境继承，工具仍以当前用户权限运行。 [Pi Shell 实现](https://github.com/earendil-works/pi/blob/v1.6.0/packages/coding-agent/src/utils/shell.ts) · [Pi 设置](https://github.com/earendil-works/pi/blob/v1.6.0/packages/coding-agent/docs/settings.md)

## 本机验证

用官方 arm64 包、本机已有的 OpenAI 兼容服务 API key、真实模型和临时 Loci 资料库。PATH 只保留系统目录和应用 helper 目录，Node 和 Bun 都不可见。Pi 配置通过隔离目录和环境变量注入，用户的 Pi 配置只用于读取已有凭据。

| 验证 | 观察到的结果 |
|---|---|
| 模型列表 | 同一套隔离环境下的 `--list-models` 能列出配置的服务商和模型 |
| PiDriver RPC | `get_state` 建立会话，真实模型流式回复指定文字，驱动返回 `.completed` |
| Soul、记忆 | 走 `LocalHost` 的主对话，在测试资料库写入两条记号，模型同时答出了来自 Soul 和记忆的值 |
| `loci` | 模型自己调用 Bash，执行 `"$LOCI" search … --json`，实际 `LociTool` 经 Unix socket 从 Host 取回资料 ID，模型答复含同一个 ID |
| 面板 | 真实模型用 `loci panel list` 列出面板，再用 `loci panel save` 保存测试面板，Host 读回同一个面板 |

关闭了 Pi 扩展、MCP、技能、提示模板和项目授权，保留 Host 写入的 `AGENTS.md`。真实服务只验证了兼容 OpenAI 这一种配置，面板定时刷新和每日回顾写入记忆待验。

## 1.6.5 接入

**组件。** 复用 `LociMedia` 的下载、进度和暂存入口，`LociStore` 负责磁盘安装。给资产声明固定版本、架构、SHA-256 和归档格式，支持 tar.gz 及外层 `pi/`。把摘要随 Loci 发版钉住，校验压缩包后才在暂存目录解包，限定条目在包目录内。对正式签名的组件复核签名与版本，用同一组启动参数做 `get_state` 冒烟，再切换活动版本。保留原目录给在跑的会话，安装失败继续使用旧包。下载共享一个任务，重试沿用相同的固定版本。先让上游提供已公证的资产，若采用 Loci 签发的组件，则由发布流程签名、公证，再更新两种架构的摘要。设置和应用启动均无需运行 Pi 的自更新。 [组件下载](../../Sources/LociHost/Library/Equipment.swift) · [组件安装](../../Sources/LociStore/Support.swift)

**M-S2。** `LociModel` 增加模型服务、设置命令与组件状态。 `LociStore` 保存服务商、模型和地址等非敏感设置，钥匙串保存 key。 `LociHost` 在没有外装 agent CLI 的首次启动引导到模型服务页，通过一次实际模型请求判定「试一下」的结果，填好后按需下载组件并选择自带 Pi。 `LociAgents` 从 Host 取得已校验的绝对路径、专用配置目录和最小环境，通过 `PiDriver` 注入。复用 `AgentRun`、`ToolGateway` 和 `LociTool`，保留生成的 `AGENTS.md`、每轮记忆前缀及 `LOCI`、`LOCI_SOCKET`、`LOCI_SESSION`。设置及错误文案由 `LociUI` 提供中英两份。 [回合启动](../../Sources/LociHost/Loci/AgentRun.swift) · [命令入口](../../Sources/LociHost/Tool/ToolGateway.swift)

**M-S3。** 给自带 Pi 单独的 `Provider` 值并复用 Pi 的思考档位及 RPC 实现。已保存的 `.pi` 继续代表系统 Pi，两边会话句柄按 provider 分开。 `InstalledAgents` 合并组件的安装、验证状态和 CLI 探测结果，`RuntimeMenu` 在现有「+」菜单中显示自带 Pi 和已安装的 Codex、Claude Code。选了自带 Pi 但组件或 key 尚未就绪时，进入模型服务页继续设置。模型列表用同一套隔离环境查询 Pi，按已配置服务筛选，服务切换后换用该服务的模型并作废缓存、下一轮重开会话。覆盖已保存 Runtime 的解码、安装状态变化后菜单刷新和三种选择各自的会话恢复。 [Runtime](../../Sources/LociModel/Runtime.swift) · [探测与模型列表](../../Sources/LociHost/HostEnvironment.swift) · [会话切换](../../Sources/LociHost/Loci/SessionRotation.swift) · [菜单](../../Sources/LociUI/Support/AgentMenus.swift)

首次启动跳转、钥匙串、组件安装更新、Intel 真机、签名与公证交付，以及「+」菜单选择都属于接入阶段的验收。本次验证使用隔离启动器接入现有 Host。
